// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.12 <0.9.0;

/**
 * @title Lottery
 * @dev A blockchain lottery
 * @custom:dev-run-script ./scripts/deploy_with_ethers.ts
 */
contract Lottery {
    /// Reentrancy has been detected.
    error ReentrancyError();
    
    /// There is no active lottery.
    error LotteryInactiveError();

    // The lottery is still active and is not ready to be ended.
    error LotteryActiveError();

    /// The calling address is not the operator.
    error NotOperatorError();

    /// The calling address is not the contract owner.
    error NotOwnerError();

    /// The calling address is not an eligible player.
    error NotPlayerError();

    /// The calling address is not payable.
    error NotPayableError();

    /// This contract does not have the funds requested.
    error InsufficientFundsError(uint contractBalance, uint requestedValue);

    // A record of a completed lottery.
    event LotteryEvent(uint indexed lotteryBlockStart, address indexed winningAddress, uint indexed winnerPrize);

    // The address of all zeros. This is used as a default value.
    address private constant zeroAddress = address(0);

    // An integer between 0 and 100 representing the percentage of the "playerPrizePool" amount that the operator takes every game.
    // Note that the player always receives the entire "bonusPrizePool" amount.
    uint private constant operatorCut = 3;

    // A lock variable to prevent reentrancy. Note that a function using the lock cannot call another function that is also using the lock.
    bool private isLocked;

    // Block where the lottery started.
    uint private lotteryBlockStart;

    // The number of additional blocks after the starting block where players may purchase tickets.
    // After this duration, buying tickets is not allowed and anyone may end the lottery to distribute prizes and start a new lottery.
    // If the duration is changed, the new duration will only apply to future lotteries, not the current one.
    uint private lotteryBlockDuration;
    uint private currentLotteryBlockDuration;

    // The owner is the original operator and is able to assign themselves the operator role at any time.
    address private ownerAddress;

    // The operator is responsible for running the lottery. They must fund this contract with gas, and in return they will receive a cut of each prize.
    address private operatorAddress;

    // The price of each ticket. If the price is changed, the new price will only apply to future lotteries, not the current one.
    uint private ticketPrice;
    uint private currentTicketPrice;

    /* To ensure the safety of player money, the contract balance is accounted for by splitting it into three different places:
        // contractFunds - The money used to pay for gas. The operator can add or remove money at will.
        // playerPrizePool - The money players have paid to purchase tickets. The operator gets a cut of each prize automatically, but otherwise they cannot add or remove funds.
        // bonusPrizePool - The money that the operator has optionally added to "sweeten the pot" and provide more prize money. The operator can add funds but cannot remove them.
    */
    uint private contractFunds;
    uint private playerPrizePool;
    uint private bonusPrizePool;

    // Variables to keep track of who is playing and how many tickets they have.
    uint private currentTicketNumber;
    mapping(uint => address) private map_ticket2Address;
    mapping(address => uint) private map_address2NumTickets;

    // Mapping of addresses to the prize winnings they have yet to claim.
    mapping(address => uint) private map_address2Winnings;

    /*
        Contract Functions
    */

    constructor(uint initialTicketPrice, uint initialLotteryBlockDuration) payable {
        // When deploying this contract, initial funds should be paid to allow for smooth lottery operation.
        addContractFunds(msg.value);

        ownerAddress = msg.sender;
        operatorAddress = msg.sender;

        lotteryBlockDuration = initialLotteryBlockDuration; //30 for testing, something larger for real.
        ticketPrice = initialTicketPrice; //1e16 // 0.01 ETH

        startNewLottery();
    }

    receive() external payable {
        // Funds received from a player will be used to buy tickets. Funds received from the operator will be used to fund the contract.
        lock_start();

        address sender = msg.sender;
        uint value = msg.value;

        if(isOperatorAddress(sender)) {
            addContractFunds(value);
        }
        else {
            requireLotteryActive();
            requirePayableAddress(msg.sender);
            requirePlayerAddress(msg.sender);

            buyTickets(sender, value);
        }

        lock_end();
    }

    fallback() external payable {
        // There is no legitimate reason for this to be called.
        consumeAllGas();
    }

    /*
        Lottery Functions
    */

    function buyTickets(address playerAddress, uint value) private {
        // Purchase as many tickets as possible for the address with the provided value. Note that tickets can only be purchased in whole number quantities.
        // After spending all the funds on tickets, anything left over will be added to the address's winnings balance that they can withdraw.
        addPlayerPrizePool(value);

        uint numTickets = value / currentTicketPrice;
        uint totalTicketValue = numTickets * currentTicketPrice;

        map_address2Winnings[playerAddress] += value - totalTicketValue;

        map_address2NumTickets[playerAddress] += numTickets;
        for(uint i = 0; i < numTickets; i++) {
            map_ticket2Address[currentTicketNumber++] = playerAddress;
        }
    }

    function startNewLottery() private {
        // Reset lottery state and begin a new lottery.
        for(uint i = 0; i < currentTicketNumber; i++) {
            address playerAddress = map_ticket2Address[i];

            // To save gas, don't call delete if we don't have to.
            if(map_address2NumTickets[playerAddress] != 0) {
                delete(map_address2NumTickets[playerAddress]);
            }
            
            // We don't need to clear "map_ticket2Address" here. When we run the next lottery, any remaining data will either be overwritten or unused.
        }

        currentTicketNumber = 0;
        playerPrizePool = 0;
        bonusPrizePool = 0;

        // If any of these values have been changed by the operator, update them now before starting the next lottery.
        currentLotteryBlockDuration = lotteryBlockDuration;
        currentTicketPrice = ticketPrice;

        lotteryBlockStart = block.number;
    }

    function endCurrentLottery() private {
        if(isZeroPlayerGame()) {
            // No one played.
            emit LotteryEvent(lotteryBlockStart, address(0), 0);
        }
        else if(isOnePlayerGame()) {
            // Since only one person has played, just give them the entire prize.
            address winningAddress = map_ticket2Address[0];

            uint winnerPrize = bonusPrizePool + playerPrizePool;

            map_address2Winnings[winningAddress] += winnerPrize;

            emit LotteryEvent(lotteryBlockStart, winningAddress, winnerPrize);
        }
        else {
            // Give the lottery operator their cut of the pot, and then give the rest to a randomly chosen winner.
            uint winningTicket = chooseWinningTicket(currentTicketNumber);
            address winningAddress = map_ticket2Address[winningTicket];
            
            uint operatorPrize = playerPrizePool * operatorCut / 100;
            uint winnerPrize = playerPrizePool + bonusPrizePool - operatorPrize;

            map_address2Winnings[getOperatorAddress()] += operatorPrize;
            map_address2Winnings[winningAddress] += winnerPrize;

            emit LotteryEvent(lotteryBlockStart, winningAddress, winnerPrize);
        }

        startNewLottery();
    }

    function isLotteryActive() private view returns (bool) {
        return block.number - lotteryBlockStart <= lotteryBlockDuration;
    }

    function requireLotteryActive() private view {
        if(!isLotteryActive()) {
            revert LotteryInactiveError();
        }
    }

    function requireLotteryInactive() private view {
        if(isLotteryActive()) {
            revert LotteryActiveError();
        }
    }

    function totalAddressTickets(address playerAddress) private view returns (uint) {
        return map_address2NumTickets[playerAddress];
    }

    function totalTickets() private view returns (uint) {
        return currentTicketNumber;
    }

    function isZeroPlayerGame() private view returns (bool) {
        // Check to see if there are no players.
        return currentTicketNumber == 0;
    }

    function isOnePlayerGame() private view returns (bool) {
        // Check to see if there is only one player who has purchased all the tickets.
        // We assume there is at least one ticket.
        address firstPlayer = map_ticket2Address[0];
        return totalAddressTickets(firstPlayer) == totalTickets();
    }

    function isAddressPlaying(address playerAddress) private view returns (bool) {
        return map_address2NumTickets[playerAddress] != 0;
    }

    function chooseWinningTicket(uint numTickets) private view returns (uint) {
        // This should only be called if at least two different players have purchased tickets.
        uint winningTicket = randomInt(numTickets);
        return winningTicket;
    }

    function setLotteryBlockDuration(uint newLotteryBlockDuration) private {
        // Do not set the current lottery block duration here. When the next lottery starts, the current lottery block duration will be updated.
        lotteryBlockDuration = newLotteryBlockDuration;
    }

    function getLotteryBlockDuration() private view returns (uint) {
        // Return the current lottery block duration.
        return currentLotteryBlockDuration;
    }

    function setTicketPrice(uint newTicketPrice) private {
        // Do not set the current ticket price here. When the next lottery starts, the current ticket price will be updated.
        ticketPrice = newTicketPrice;
    }

    function getTicketPrice() private view returns (uint) {
        // Return the current ticket price.
        return currentTicketPrice;
    }

    function withdrawAddressWinnings(address playerAddress) private {
        uint winnings = map_address2Winnings[playerAddress];
        map_address2Winnings[playerAddress] = 0;
        transferToAddress(playerAddress, winnings);
    }

    function getAddressWinnings(address playerAddress) private view returns (uint) {
        return map_address2Winnings[playerAddress];
    }

    /*
        RNG Functions
    */

    function randomInt(uint N) private view returns (uint) {
        // Generate a random integer 0 <= n < N.
        uint randomHash = uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp)));
        return randomHash % N;
    }

    /*
        Address Restriction Functions
    */

    function setOwnerAddress(address newOwnerAddress) private {
        ownerAddress = newOwnerAddress;
    }

    function getOwnerAddress() private view returns (address) {
        return ownerAddress;
    }

    function isOwnerAddress(address sender) private view returns (bool) {
        return sender == getOwnerAddress();
    }

    function requireOwnerAddress(address sender) private view {
        if(!isOwnerAddress(sender)) {
            revert NotOwnerError();
        }
    }

    function setOperatorAddress(address newOperatorAddress) private {
        operatorAddress = newOperatorAddress;
    }

    function getOperatorAddress() private view returns (address) {
        return operatorAddress;
    }

    function isOperatorAddress(address sender) private view returns (bool) {
        return sender == getOperatorAddress();
    }

    function requireOperatorAddress(address sender) private view {
        if(!isOperatorAddress(sender)) {
            revert NotOperatorError();
        }
    }

    function isPlayerAddress(address sender) private view returns (bool) {
        // The only ineligible player is the operator.
        return sender != getOperatorAddress();
    }

    function requirePlayerAddress(address sender) private view {
        if(!isPlayerAddress(sender)) {
            revert NotPlayerError();
        }
    }

    function isPayableAddress(address testAddress) private returns (bool) {
        // If the address is payable, this no-op transfer should succeed.
        return payable(testAddress).send(0);
    }

    function requirePayableAddress(address testAddress) private {
        if(!isPayableAddress(testAddress)) {
            revert NotPayableError();
        }
    }

    /*
        Funding Functions
    */

    function getContractBalance() private view returns (uint) {
        // This is the true contract balance. This includes everything, including player funds.
        return address(this).balance;
    }

    function addContractFunds(uint value) private {
        contractFunds += value;
    }

    function removeContractFunds(uint value) private {
        // Transfer an amount from the contract balance to the operator.
        uint operatorContractBalance = getOperatorContractBalance();

        if(value > operatorContractBalance) {
            revert InsufficientFundsError(operatorContractBalance, value);
        }

        // If the value is higher than the extra funds, subtract the difference from "contractFunds". This accounting makes it so extra funds are spent first.
        if(value > getExtraContractBalance()) {
            contractFunds -= (value - getExtraContractBalance());
        }
        transferToAddress(getOperatorAddress(), value);
    }

    function removeAllContractFunds() private {
        // Transfer the entire contract balance to the operator.
        contractFunds = 0;
        transferToAddress(getOperatorAddress(), getOperatorContractBalance());
    }

    function getContractFunds() private view returns (uint) {
        return contractFunds;
    }

    function addPlayerPrizePool(uint value) private {
        // Add funds to the player prize pool.
        playerPrizePool += value;
    }

    function getPlayerPrizePool() private view returns (uint) {
        return playerPrizePool;
    }

    function addBonusPrizePool(uint value) private {
        // Add funds to the bonus prize pool.
        bonusPrizePool += value;
    }

    function getBonusPrizePool() private view returns (uint) {
        return bonusPrizePool;
    }

    function getAccountedContractBalance() private view returns (uint) {
        return contractFunds + playerPrizePool + bonusPrizePool;
    }

    function getExtraContractBalance() private view returns (uint) {
        // Returns the amount of "extra" funds this contract has. This should usually be zero, but may be more if funds are sent here in ways that cannot be accounted for.
        // For example, a coinbase transaction or another contract calling "selfdestruct" could send funds here without passing through the "receive" function for proper accounting.
        assert(getContractBalance() >= getAccountedContractBalance());
        return getContractBalance() - getAccountedContractBalance();
    }

    function getOperatorContractBalance() private view returns (uint) {
        // This is the balance that the operator has access to.
        return contractFunds + getExtraContractBalance();
    }

    /*
        Reentrancy Functions
    */

    function setLock(bool newIsLocked) private {
        isLocked = newIsLocked;
    }

    function getLock() private view returns (bool) {
        return isLocked;
    }

    function lock_start() private {
        // Call this at the start of each external function. If the lock is already set, we error to prevent reentrancy.
        if(getLock()) {
            revert ReentrancyError();
        }
        setLock(true);
    }

    function lock_end() private {
        // Call this at the end of each external function.
        setLock(false);
    }

    /*
        Utility Functions
    */

    function transferToAddress(address recipientAddress, uint value) private {
        // The caller is responsible for making sure that the address is actually payable.
        payable(recipientAddress).transfer(value);
    }

    function consumeAllGas() private pure {
        // This operation will cause a revert but also consume all the gas.
        // Because we may not have enough gas to perform any operations, we simply allow this gas to be unaccounted for (i.e. extra funds).
        assembly("memory-safe") { invalid() }
    }

    /*
        External Functions
    */

    function action_unlock() external {
        // The operator can call this to unlock (not lock) the contract. This is a fail-safe in case something unanticipated has happened.
        requireOperatorAddress(msg.sender);
        setLock(false);
    }

    function action_addContractFunds() external payable {
        // The operator can call this to give gas to the contract.
        lock_start();

        requireOperatorAddress(msg.sender);

        addContractFunds(msg.value);

        lock_end();
    }

    function action_addBonusPrizePool() external payable {
        // Anyone can add funds to the bonus prize pool.
        lock_start();

        addBonusPrizePool(msg.value);

        lock_end();
    }

    function action_buyTickets() external payable {
        // Players can call this to buy tickets for the lottery, but only if it is still active.
        lock_start();

        requireLotteryActive();
        requirePayableAddress(msg.sender);
        requirePlayerAddress(msg.sender);

        buyTickets(msg.sender, msg.value);

        lock_end();
    }

    function action_endCurrentLottery() external {
        // Anyone can call this to end the current lottery, but only if it is no longer active.
        lock_start();

        requireLotteryInactive();

        endCurrentLottery();

        lock_end();
    }

    function action_removeContractFunds(uint value) external {
        // XYZ RENAME to withdraw?
        lock_start();

        requireOperatorAddress(msg.sender);

        removeContractFunds(value);

        lock_end();
    }

    function action_removeAllContractFunds() external {
        // XYZ
        lock_start();

        requireOperatorAddress(msg.sender);

        removeAllContractFunds();

        lock_end();
    }

    function action_setOwnerAddress(address newOwnerAddress) external {
        // The current owner can transfer ownership to a new address.
        lock_start();

        requireOwnerAddress(msg.sender);

        setOwnerAddress(newOwnerAddress);

        lock_end();
    }

    function action_setOperatorAddress(address newOperatorAddress) external {
        // The current operator can assign the operator role to a new address.
        lock_start();

        requireOperatorAddress(msg.sender);

        setOperatorAddress(newOperatorAddress);

        lock_end();
    }

    function action_setOperatorAddressToOwner() external {
        // The owner can call this to make themselves the operator.
        lock_start();

        requireOwnerAddress(msg.sender);

        setOperatorAddress(msg.sender);

        lock_end();
    }

    function action_setLotteryBlockDuration(uint newLotteryBlockDuration) external {
        lock_start();

        requireOperatorAddress(msg.sender);

        setLotteryBlockDuration(newLotteryBlockDuration);

        lock_end();
    }

    function action_setTicketPrice(uint newTicketPrice) external {
        lock_start();

        requireOperatorAddress(msg.sender);

        setTicketPrice(newTicketPrice);

        lock_end();
    }

    function action_withdrawAddressWinnings() external {
        // Anyone can manually transfer their winnings to their address.
        lock_start();

        withdrawAddressWinnings(msg.sender);

        lock_end();
    }

    function action_withdrawOtherAddressWinnings(address playerAddress) external {
        // The operator can trigger a withdraw for someone else.
        lock_start();

        requireOperatorAddress(msg.sender);

        withdrawAddressWinnings(playerAddress);

        lock_end();
    }

    function query_getLock() external view returns (bool) {
        return getLock();
    }

    function query_getContractBalance() external view returns (uint) {
        return getContractBalance();
    }

    function query_totalAddressTickets(address playerAddress) external view returns (uint) {
        return totalAddressTickets(playerAddress);
    }

    function query_totalTickets() external view returns (uint) {
        return totalTickets();
    }

    function query_getAddressWinnings(address playerAddress) external view returns (uint) {
        return getAddressWinnings(playerAddress);
    }

    function query_isAddressPlaying(address playerAddress) external view returns (bool) {
        return isAddressPlaying(playerAddress);
    }

    function query_addressWinChance(address playerAddress) external view returns (uint) {
        // Returns the predicted number of times that the address will win out of 100 times, truncated to the nearest integer.
        // This is equivalent to the percentage probability of the address winning.
        return totalAddressTickets(playerAddress) * 100 / totalTickets();
    }

    function query_addressWinChanceOutOf(address playerAddress, uint N) external view returns (uint) {
        // Returns the predicted number of times that the address will win out of N times, truncated to the nearest integer.
        // This function can be used to get extra digits in the answer that would normally get truncated.
        return totalAddressTickets(playerAddress) * N / totalTickets();
    }

    function query_isLotteryActive() external view returns (bool) {
        return isLotteryActive();
    }

    function query_getOwnerAddress() external view returns (address) {
        return getOwnerAddress();
    }

    function query_getOperatorAddress() external view returns (address) {
        return getOperatorAddress();
    }

    function query_getContractFunds() external view returns (uint) {
        return getContractFunds();
    }

    function query_getPlayerPrizePool() external view returns (uint) {
        return getPlayerPrizePool();
    }

    function query_getBonusPrizePool() external view returns (uint) {
        return getBonusPrizePool();
    }

    function query_getLotteryBlockDuration() external view returns (uint) {
        return getLotteryBlockDuration();
    }

    function query_getTicketPrice() external view returns (uint) {
        return getTicketPrice();
    }
}