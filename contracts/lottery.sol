// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.12 <0.9.0;

/**
 * @title The Musicslayer Lottery
 * @author Musicslayer
 */
contract MusicslayerLottery {
    /// @notice Reentrancy has been detected.
    error ReentrancyError();
    
    /// @notice There is no active lottery.
    error LotteryInactiveError();

    /// @notice The lottery is still active and is not ready to be ended.
    error LotteryActiveError();

    /// @notice The calling address is not the operator.
    error NotOperatorError();

    /// @notice The calling address is not the contract owner.
    error NotOwnerError();

    /// @notice The calling address is not the contract owner or the operator.
    error NotOwnerOrOperatorError();

    /// @notice The calling address is not an eligible player.
    error NotPlayerError();

    /// @notice The calling address is not payable.
    error NotPayableError();

    /// @notice This contract does not have the funds requested.
    error InsufficientFundsError(uint contractBalance, uint requestedValue);

    /// @notice A record of the owner address changing.
    event OwnerChanged(address indexed oldOwnerAddress, address indexed newOwnerAddress);

    /// @notice A record of the operator address changing.
    event OperatorChanged(address indexed oldOperatorAddress, address indexed newOperatorAddress);

    /// @notice A record of a lottery starting.
    event LotteryStart(uint indexed lotteryNumber, uint indexed lotteryBlockStart, uint indexed lotteryBlockDuration, uint ticketPrice);

    /// @notice A record of a lottery ending.
    event LotteryEnd(uint indexed lotteryNumber, uint indexed lotteryBlockStart, address indexed winningAddress, uint winnerPrize);

    /// @notice A record of a lottery being canceled.
    event LotteryCancel(uint indexed lotteryNumber, uint indexed lotteryBlockStart);

    // An integer between 0 and 100 representing the percentage of the "playerPrizePool" amount that the operator takes every game.
    // Note that the player always receives the entire "bonusPrizePool" amount.
    uint private constant operatorCut = 10;

    // A lock variable to prevent reentrancy. Note that a function using the lock cannot call another function that is also using the lock.
    bool private isLocked;

    // The current lottery number.
    uint private lotteryNumber;

    // Block where the lottery started.
    uint private lotteryBlockStart;

    // The number of additional blocks after the starting block where players may purchase tickets.
    // After this duration, buying tickets is not allowed and anyone may end the lottery to distribute prizes and start a new lottery.
    // If the duration is changed, the new duration will only apply to future lotteries, not the current one.
    uint private lotteryBlockDuration;
    uint private currentLotteryBlockDuration;

    // The owner is the original operator and is able to assign themselves the operator role at any time.
    address private ownerAddress;

    // The operator is responsible for running the lottery. In return, they will receive a cut of each prize.
    address private operatorAddress;

    // The price of each ticket. If the price is changed, the new price will only apply to future lotteries, not the current one.
    uint private ticketPrice;
    uint private currentTicketPrice;

    /* To ensure the safety of player funds, the contract balance is accounted for by splitting it into different places:
        // contractFunds - The general funds owned by the contract. The operator can add or withdraw funds at will.
        // playerPrizePool - The funds players have paid to purchase tickets. The operator cannot add or withdraw funds.
        // bonusPrizePool - The funds that have optionally been added to "sweeten the pot" and provide a bigger prize. The operator can add funds but cannot withdraw them.
        // claimableBalancePool - The funds that have not yet been claimed. The operator takes their cut from here, but otherwise they cannot add or withdraw funds.
       Anything else not accounted for is considered to be "extra" funds that are treated the same as contract funds.
    */
    uint private contractFunds;
    uint private playerPrizePool;
    uint private bonusPrizePool;
    uint private claimableBalancePool;

    // Variables to keep track of who is playing and how many tickets they have.
    uint private currentTicketNumber;
    mapping(uint => address) private map_ticket2Address;
    mapping(address => uint) private map_address2NumTickets;

    // Mapping of addresses to claimable balances.
    // For players, this balance is from winnings or from leftover funds after purchasing tickets.
    // For the operator, this balance is from their cut of the prize.
    mapping(address => uint) private map_address2ClaimableBalance;

    /*
        Contract Functions
    */

    constructor(uint initialLotteryBlockDuration, uint initialTicketPrice) payable {
        addContractFunds(msg.value);

        setOwnerAddress(msg.sender);
        setOperatorAddress(msg.sender);

        lotteryBlockDuration = initialLotteryBlockDuration;
        ticketPrice = initialTicketPrice;

        startNewLottery();
    }

    receive() external payable {
        // Funds received from a player will be used to buy tickets. Funds received from the operator will be counted as contract funds.
        lock_start();

        if(isOperatorAddress(msg.sender)) {
            addContractFunds(msg.value);
        }
        else {
            requireLotteryActive();
            requirePayableAddress(msg.sender);
            requirePlayerAddress(msg.sender);

            buyTickets(msg.sender, msg.value);
        }

        lock_end();
    }

    fallback() external payable {
        // There is no legitimate reason for this fallback function to be called.
        consumeAllGas();
    }

    /*
        Lottery Functions
    */

    function buyTickets(address _address, uint value) private {
        // Purchase as many tickets as possible for the address with the provided value. Note that tickets can only be purchased in whole number quantities.
        // After spending all the funds on tickets, anything left over will be added to the address's claimable balance.
        uint numTickets = value / currentTicketPrice;
        uint totalTicketValue = numTickets * currentTicketPrice;
        uint unspentValue = value - totalTicketValue;

        addPlayerPrizePool(totalTicketValue);
        addAddressClaimableBalance(_address, unspentValue);

        map_address2NumTickets[_address] += numTickets;
        for(uint i = 0; i < numTickets; i++) {
            map_ticket2Address[currentTicketNumber++] = _address;
        }
    }

    function startNewLottery() private {
        // Reset lottery state and begin a new lottery.
        for(uint i = 0; i < currentTicketNumber; i++) {
            address _address = map_ticket2Address[i];

            // To save gas, don't call delete if we don't have to.
            if(map_address2NumTickets[_address] != 0) {
                delete(map_address2NumTickets[_address]);
            }
            
            // We don't need to clear "map_ticket2Address" here. When we run the next lottery, any remaining data will either be overwritten or unused.
        }

        currentTicketNumber = 0;
        playerPrizePool = 0;
        bonusPrizePool = 0;

        // If any of these values have been changed by the operator, update them now before starting the next lottery.
        currentLotteryBlockDuration = lotteryBlockDuration;
        currentTicketPrice = ticketPrice;

        lotteryNumber++;
        lotteryBlockStart = block.number;

        emit LotteryStart(lotteryNumber, lotteryBlockStart, lotteryBlockDuration, ticketPrice);
    }

    function endCurrentLottery() private {
        // Choose a winner to end the current lottery, credit any prizes rewarded, and then start a new lottery.
        if(isZeroPlayerGame()) {
            // No one played. For recordkeeping purposes, the winner is the zero address and the prize is zero.
            emit LotteryEnd(lotteryNumber, lotteryBlockStart, address(0), 0);
        }
        else if(isOnePlayerGame()) {
            // Since only one person has played, just give them the entire prize. Don't bother picking a random ticket.
            address winningAddress = map_ticket2Address[0];

            uint winnerPrize = bonusPrizePool + playerPrizePool;

            addAddressClaimableBalance(winningAddress, winnerPrize);

            emit LotteryEnd(lotteryNumber, lotteryBlockStart, winningAddress, winnerPrize);
        }
        else {
            // Give the lottery operator their cut of the pot, and then give the rest to a randomly chosen winner.
            uint winningTicket = chooseWinningTicket(currentTicketNumber);
            address winningAddress = map_ticket2Address[winningTicket];
            
            uint operatorPrize = playerPrizePool * operatorCut / 100;
            uint winnerPrize = playerPrizePool + bonusPrizePool - operatorPrize;

            addAddressClaimableBalance(getOperatorAddress(), operatorPrize);
            addAddressClaimableBalance(winningAddress, winnerPrize);

            emit LotteryEnd(lotteryNumber, lotteryBlockStart, winningAddress, winnerPrize);
        }

        startNewLottery();
    }

    function cancelCurrentLottery() private {
        // Refund everyone and then start a new lottery. All refunds will be accounted for as claimable balances.

        // To avoid double counting and to keep things simple, we refund each ticket one at a time.
        for(uint i = 0; i < currentTicketNumber; i++) {
            addAddressClaimableBalance(map_ticket2Address[i], currentTicketPrice);
        }

        emit LotteryCancel(lotteryNumber, lotteryBlockStart);

        startNewLottery();
    }

    function isLotteryActive() private view returns (bool) {
        return block.number - lotteryBlockStart <= currentLotteryBlockDuration;
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

    function totalAddressTickets(address _address) private view returns (uint) {
        return map_address2NumTickets[_address];
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
        address firstAddress = map_ticket2Address[0];
        return totalAddressTickets(firstAddress) == totalTickets();
    }

    function isAddressPlaying(address _address) private view returns (bool) {
        return map_address2NumTickets[_address] != 0;
    }

    function chooseWinningTicket(uint numTickets) private view returns (uint) {
        // Use a random process to choose a winning ticket out of all possible tickets entered into the current lottery.
        return randomInt(numTickets);
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

    function setOwnerAddress(address _address) private {
        emit OwnerChanged(ownerAddress, _address);
        ownerAddress = _address;
    }

    function getOwnerAddress() private view returns (address) {
        return ownerAddress;
    }

    function isOwnerAddress(address _address) private view returns (bool) {
        return _address == getOwnerAddress();
    }

    function requireOwnerAddress(address _address) private view {
        if(!isOwnerAddress(_address)) {
            revert NotOwnerError();
        }
    }

    function setOperatorAddress(address newOperatorAddress) private {
        emit OperatorChanged(operatorAddress, newOperatorAddress);
        operatorAddress = newOperatorAddress;
    }

    function getOperatorAddress() private view returns (address) {
        return operatorAddress;
    }

    function isOperatorAddress(address _address) private view returns (bool) {
        return _address == getOperatorAddress();
    }

    function requireOperatorAddress(address _address) private view {
        if(!isOperatorAddress(_address)) {
            revert NotOperatorError();
        }
    }

    function isOwnerOrOperatorAddress(address _address) private view returns (bool) {
        return isOwnerAddress(_address) || isOperatorAddress(_address);
    }

    function requireOwnerOrOperatorAddress(address _address) private view {
        if(!isOwnerOrOperatorAddress(_address)) {
            revert NotOwnerOrOperatorError();
        }
    }

    function isPlayerAddress(address _address) private view returns (bool) {
        // The only ineligible player is the operator.
        return _address != getOperatorAddress();
    }

    function requirePlayerAddress(address _address) private view {
        if(!isPlayerAddress(_address)) {
            revert NotPlayerError();
        }
    }

    function isPayableAddress(address _address) private returns (bool) {
        // If the address is payable, this no-op transfer should succeed.
        return payable(_address).send(0);
    }

    function requirePayableAddress(address _address) private {
        if(!isPayableAddress(_address)) {
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

    function withdrawContractFunds(address _address, uint value) private {
        // Withdraw an amount from the contract funds. For the purposes of this function, extra funds are treated as contract funds.
        uint operatorContractBalance = getOperatorContractBalance();

        if(value > operatorContractBalance) {
            revert InsufficientFundsError(operatorContractBalance, value);
        }

        // Only if the value is higher than the extra funds do we subtract from "contractFunds". This accounting makes it so extra funds are spent first.
        if(value > getExtraContractBalance()) {
            contractFunds -= (value - getExtraContractBalance());
        }
        transferToAddress(_address, value);
    }

    function withdrawAllContractFunds(address _address) private {
        // Withdraw the entire contract funds. For the purposes of this function, extra funds are treated as contract funds.
        contractFunds = 0;
        transferToAddress(_address, getOperatorContractBalance());
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
        return contractFunds + playerPrizePool + bonusPrizePool + claimableBalancePool;
    }

    function getExtraContractBalance() private view returns (uint) {
        // Returns the amount of "extra" funds this contract has. This should usually be zero, but may be more if funds are sent here in ways that cannot be accounted for.
        // For example, a coinbase transaction or another contract calling "selfdestruct" could send funds here without passing through the "receive" function for proper accounting.
        return getContractBalance() - getAccountedContractBalance();
    }

    function getOperatorContractBalance() private view returns (uint) {
        // This is the balance that the operator has access to.
        return contractFunds + getExtraContractBalance();
    }

    function addAddressClaimableBalance(address _address, uint value) private {
        map_address2ClaimableBalance[_address] += value;
        claimableBalancePool += value;
    }

    function withdrawAddressClaimableBalance(address _address) private {
        // We only allow the entire balance to be claimed.
        uint balance = map_address2ClaimableBalance[_address];

        map_address2ClaimableBalance[_address] = 0;
        claimableBalancePool -= balance;

        transferToAddress(_address, balance);
    }

    function getAddressClaimableBalance(address _address) private view returns (uint) {
        return map_address2ClaimableBalance[_address];
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
        // This operation will cause a revert but also consume all the gas. This will punish those who are trying to attack the contract.
        // As for any payable funds that may have been sent to the caller, because we may not have enough gas to perform any operations, we simply allow this amount to be unaccounted for (i.e. extra funds).
        assembly("memory-safe") { invalid() }
    }

    /*
        External Functions
    */

    /// @notice The operator can call this to unlock the contract. This is a fail-safe in case something unanticipated has happened.
    function action_unlock() external {
        // 
        requireOperatorAddress(msg.sender);
        setLock(false);
    }

    /// @notice The operator can call this to give funds to the contract.
    function action_addContractFunds() external payable {
        lock_start();

        requireOperatorAddress(msg.sender);

        addContractFunds(msg.value);

        lock_end();
    }

    /// @notice Anyone can call this to add funds to the bonus prize pool.
    function action_addBonusPrizePool() external payable {
        lock_start();

        addBonusPrizePool(msg.value);

        lock_end();
    }

    /// @notice Players can call this to buy tickets for the current lottery, but only if it is still active.
    function action_buyTickets() external payable {
        lock_start();

        requireLotteryActive();
        requirePayableAddress(msg.sender);
        requirePlayerAddress(msg.sender);

        buyTickets(msg.sender, msg.value);

        lock_end();
    }

    /// @notice Anyone can call this to end the current lottery, but only if it is no longer active.
    function action_endCurrentLottery() external {
        lock_start();

        requireLotteryInactive();

        endCurrentLottery();

        lock_end();
    }

    /// @notice The operator can call this at any time to cancel the current lottery and refund everyone. This is a fail-safe in case something unanticipated has happened.
    function action_cancelCurrentLottery() external {
        lock_start();

        requireOperatorAddress(msg.sender);
        
        cancelCurrentLottery();

        lock_end();
    }

    
    /// @notice The operator can call this to withdraw an amount of the contract funds.
    /// @param value The amounts of contract funds to withdraw.
    function action_withdrawContractFunds(uint value) external {
        lock_start();

        requireOperatorAddress(msg.sender);

        withdrawContractFunds(msg.sender, value);

        lock_end();
    }

    /// @notice The operator can call this to withdraw all contract funds.
    function action_withdrawAllContractFunds() external {
        lock_start();

        requireOperatorAddress(msg.sender);

        withdrawAllContractFunds(msg.sender);

        lock_end();
    }

    /// @notice The owner can transfer ownership to a new address.
    /// @param newOwnerAddress The new owner address.
    function action_setOwnerAddress(address newOwnerAddress) external {
        lock_start();

        requireOwnerAddress(msg.sender);

        setOwnerAddress(newOwnerAddress);

        lock_end();
    }

    /// @notice The operator can assign the operator role to a new address.
    /// @param newOperatorAddress The new operator address.
    function action_setOperatorAddress(address newOperatorAddress) external {
        lock_start();

        requireOperatorAddress(msg.sender);

        setOperatorAddress(newOperatorAddress);

        lock_end();
    }

    /// @notice The owner can call this to make themselves the operator.
    function action_setOperatorAddressToOwner() external {
        lock_start();

        requireOwnerAddress(msg.sender);

        setOperatorAddress(msg.sender);

        lock_end();
    }

    /// @notice The operator can change the duration of the lottery. This change will go into effect starting from the next lottery.
    /// @param newLotteryBlockDuration The new duration of the lottery in blocks.
    function action_setLotteryBlockDuration(uint newLotteryBlockDuration) external {
        lock_start();

        requireOperatorAddress(msg.sender);

        setLotteryBlockDuration(newLotteryBlockDuration);

        lock_end();
    }

    /// @notice The operator can change the ticket price of the lottery. This change will go into effect starting from the next lottery.
    /// @param newTicketPrice The new ticket price of the lottery.
    function action_setTicketPrice(uint newTicketPrice) external {
        lock_start();

        requireOperatorAddress(msg.sender);

        setTicketPrice(newTicketPrice);

        lock_end();
    }

    /// @notice Anyone can call this to withdraw any claimable balance they have.
    function action_withdrawAddressClaimableBalance() external {
        lock_start();

        withdrawAddressClaimableBalance(msg.sender);

        lock_end();
    }

    /// @notice The operator can trigger a claimable balance withdraw for someone else. This can be used to send funds to winners who do not know how to withdraw themselves.
    /// @param _address The address that the operator is triggering the claimable balance withdraw for.
    function action_withdrawOtherAddressClaimableBalance(address _address) external {
        lock_start();

        requireOperatorAddress(msg.sender);

        withdrawAddressClaimableBalance(_address);

        lock_end();
    }

    /// @notice Returns whether the contract is currently locked.
    /// @return Whether the contract is currently locked.
    function query_getLock() external view returns (bool) {
        return getLock();
    }

    /// @notice Returns the entire contract balance. This includes all funds, even those that are unaccounted for.
    /// @return The entire contract balance.
    function query_getContractBalance() external view returns (uint) {
        return getContractBalance();
    }

    /// @notice Returns the number of tickets an address has in the current lottery.
    /// @param _address The address that we are checking the number of tickets for.
    /// @return The number of tickets the address has in the current lottery.
    function query_totalAddressTickets(address _address) external view returns (uint) {
        return totalAddressTickets(_address);
    }

    /// @notice Returns the total number of tickets in the current lottery.
    /// @return The total number of tickets in the current lottery.
    function query_totalTickets() external view returns (uint) {
        return totalTickets();
    }

    /// @notice Returns the claimable balance of the address.
    /// @param _address The address that we are checking the claimable balance for.
    /// @return The claimable balance of the address.
    function query_getAddressClaimableBalance(address _address) external view returns (uint) {
        return getAddressClaimableBalance(_address);
    }

    /// @notice Returns whether the address is playing in the current lottery.
    /// @param _address The address that we are checking whether it is playing or not.
    /// @return Whether the address is playing or not.
    function query_isAddressPlaying(address _address) external view returns (bool) {
        return isAddressPlaying(_address);
    }

    /// @notice Returns the predicted number of times that the address will win out of 100 times, truncated to an integer. This is equivalent to the percentage probability of the address winning.
    /// @param _address The address that we are checking the win chance for.
    /// @return The predicted number of times that the address will win out of 100 times.
    function query_addressWinChance(address _address) external view returns (uint) {
        return totalAddressTickets(_address) * 100 / totalTickets();
    }

    /// @notice Returns the predicted number of times that the address will win out of N times, truncated to an integer. This function can be used to get extra digits in the answer that would normally get truncated.
    /// @param _address The address that we are checking the win chance for.
    /// @param N The total number of times that we want to know how many times the address will win out of.
    /// @return The predicted number of times that the address will win out of N times.
    function query_addressWinChanceOutOf(address _address, uint N) external view returns (uint) {
        return totalAddressTickets(_address) * N / totalTickets();
    }

    /// @notice Returns whether the current lottery is active or not.
    /// @return Whether the current lottery is active or not.
    function query_isLotteryActive() external view returns (bool) {
        return isLotteryActive();
    }

    /// @notice Returns the current owner address.
    /// @return The current owner address.
    function query_getOwnerAddress() external view returns (address) {
        return getOwnerAddress();
    }

    /// @notice Returns the current operator address.
    /// @return The current operator address.
    function query_getOperatorAddress() external view returns (address) {
        return getOperatorAddress();
    }

    /// @notice Returns the amount of funds accounted for as contract funds. Note that the actual contract balance may be higher.
    /// @return The amount of contract funds.
    function query_getContractFunds() external view returns (uint) {
        return getContractFunds();
    }

    /// @notice Returns the player prize pool. This is the amount of funds used to purchase tickets in the current lottery.
    /// @return The player prize pool.
    function query_getPlayerPrizePool() external view returns (uint) {
        return getPlayerPrizePool();
    }

    /// @notice Returns the bonus prize pool. This is the amount of bonus funds that anyone can donate to "sweeten the pot".
    /// @return The bonus prize pool.
    function query_getBonusPrizePool() external view returns (uint) {
        return getBonusPrizePool();
    }

    /// @notice Returns the duration of the current lottery in blocks.
    /// @return The duration of the current lottery in blocks.
    function query_getLotteryBlockDuration() external view returns (uint) {
        return getLotteryBlockDuration();
    }

    /// @notice Returns the ticket price of the current lottery.
    /// @return The ticket price of the current lottery.
    function query_getTicketPrice() external view returns (uint) {
        return getTicketPrice();
    }

    error InternalInfo1(
        uint operatorCut,
        bool isLocked,
        uint lotteryBlockStart,
        uint lotteryBlockDuration,
        uint currentLotteryBlockDuration,
        address ownerAddress,
        address operatorAddress,
        uint ticketPrice,
        uint currentTicketPrice,
        uint contractFunds,
        uint playerPrizePool,
        uint bonusPrizePool
    );

    /// @notice The owner or the operator can call this to get information about the internal state of the contract.
    function query_getInternalInfo1() external view {
        // We use an error as it is the easiest way to aggregate and reveal all the information we want.
        requireOwnerOrOperatorAddress(msg.sender);

        revert InternalInfo1(
            operatorCut,
            isLocked,
            lotteryBlockStart,
            lotteryBlockDuration,
            currentLotteryBlockDuration,
            ownerAddress,
            operatorAddress,
            ticketPrice,
            currentTicketPrice,
            contractFunds,
            playerPrizePool,
            bonusPrizePool
        );
    }

    error InternalInfo2(
        uint claimableBalancePool,
        uint currentTicketNumber
    );

    /// @notice The owner or the operator can call this to get information about the internal state of the contract.
    function query_getInternalInfo2() external view {
        // We use an error as it is the easiest way to aggregate and reveal all the information we want.
        requireOwnerOrOperatorAddress(msg.sender);

        revert InternalInfo2(
            claimableBalancePool,
            currentTicketNumber
        );
    }
}