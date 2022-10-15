// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.12 <0.9.0;

/**
 * @title Lottery
 * @dev A blockchain lottery
 * @custom:dev-run-script ./scripts/deploy_with_ethers.ts
 */
contract Lottery {
    /// This contract is currently disabled.
    error ContractDisabled();

    /// The calling address is not the operator.
    error NotOperator();

    /// The calling address is not an eligible player.
    error NotPlayer();

    /// The calling address is not payable.
    error NotPayable();

    /// This contract does not have the funds requested.
    error InsufficientFunds(uint contractBalance, uint requestedValue);

    // An integer between 0 and 100 representing the percentage of the "playerPrizePool" amount that the operator takes every game.
    // Note that the player always receives the entire "bonusPrizePool" amount.
    uint private constant operatorCut = 3;

    // The price of each ticket. Tickets must be purchased in integer quantities.
    uint private constant ticketPrice = 1e16; // 0.01 ETH

    // Switch to turn the lottery on and off.
    bool private isContractEnabled;

    // The operator is responsible for running the lottery. They must fund this contract with gas, and in return they will receive a cut of each prize.
    address private operatorAddress = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;

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
    address[] private list_address;
    mapping(uint => address) private map_ticket2Address;
    mapping(address => uint) private map_address2NumTickets;

    /*
        Contract Functions
    */

    constructor(address /*initialOperatorAddress*/) payable {
        // When deploying this contract, initial funds should be paid to allow for smooth lottery operation.
        isContractEnabled = true;
        addContractFunds(msg.value);
    }

    receive() external payable {
        // If a player sends money, then give them tickets. If the operator sends money, then add it directly to the bonus prize pool.
        address sender = msg.sender;
        uint value = msg.value;

        if(isOperatorAddress(sender)) {
            addBonusPrizePool(value);
        }
        else {
            requireContractEnabled();
            buyTickets(sender, value);
        }
    }

    function fundContract(uint value) private {
        addContractFunds(value);
    }

    function getContractBalance() private view returns (uint) {
        // This is the true contract balance. This includes everything, including player funds.
        return address(this).balance;
    }

    /*
        Lottery Functions
    */

    function buyTickets(address playerAddress, uint value) private {
        // Each ticket has a fixed cost. After spending all the funds on tickets, anything left over will be given back to the player.
        uint numTickets = value / ticketPrice;
        uint totalTicketValue = numTickets * ticketPrice;

        addPlayerPrizePool(totalTicketValue);
        value -= totalTicketValue;

        if(!isAddressPlaying(playerAddress)) {
            list_address.push(playerAddress);
        }

        map_address2NumTickets[playerAddress] += numTickets;
        for(uint i = 0; i < numTickets; i++) {
            map_ticket2Address[currentTicketNumber++] = playerAddress;
        }

        sendToAddress(playerAddress, value);
    }

    function endLottery() private {
        if(isZeroPlayerGame()) {
            // No one played, so just do nothing.
        }
        else if(isOnePlayerGame()) {
            // Since only one person has played, just give them the entire prize.
            address winningAddress = map_ticket2Address[0];

            uint winnerPrize = bonusPrizePool + playerPrizePool;

            resetLottery();
            sendToAddress(winningAddress, winnerPrize);
        }
        else {
            // Give the lottery operator their cut of the pot, and then give the rest to a randomly chosen winner.
            uint winningTicket = chooseWinningTicket(currentTicketNumber);
            address winningAddress = map_ticket2Address[winningTicket];
            
            uint operatorPrize = playerPrizePool * operatorCut / 100;
            uint winnerPrize = playerPrizePool + bonusPrizePool - operatorPrize;

            resetLottery();
            sendToAddress(getOperatorAddress(), operatorPrize);
            sendToAddress(winningAddress, winnerPrize);
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
        return list_address.length == 1;
    }

    function isAddressPlaying(address playerAddress) private view returns (bool) {
        return map_address2NumTickets[playerAddress] != 0;
    }

    function chooseWinningTicket(uint numTickets) private view returns (uint) {
        // This should only be called if at least two different players have purchased tickets.
        uint winningTicket = randomInt(numTickets);
        return winningTicket;
    }

    function resetLottery() private {
        for(uint i = 0; i < currentTicketNumber; i++) {
            delete map_ticket2Address[i];
        }

        for(uint i = 0; i < list_address.length; i++) {
            delete map_address2NumTickets[list_address[i]];
        }

        delete list_address;

        currentTicketNumber = 0;
        playerPrizePool = 0;
        bonusPrizePool = 0;
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
        Control Functions
    */

    function setContractEnabled(bool isEnabled) private {
        isContractEnabled = isEnabled;
    }

    function getContractEnabled() private view returns (bool) {
        return isContractEnabled;
    }

    function requireContractEnabled() private view {
        if(!getContractEnabled()) {
            revert ContractDisabled();
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
            revert NotOperator();
        }
    }

    function isPlayerAddress(address sender) private view returns (bool) {
        // The only ineligible player is the operator.
        return sender != getOperatorAddress();
    }

    function requirePlayerAddress(address sender) private view {
        if(!isPlayerAddress(sender)) {
            revert NotPlayer();
        }
    }

    function isPayableAddress(address testAddress) private returns (bool) {
        // If the address is payable, this no-op transfer should succeed.
        return payable(testAddress).send(0);
    }

    function requirePayableAddress(address testAddress) private {
        if(!isPayableAddress(testAddress)) {
            revert NotPayable();
        }
    }

    /*
        Funding Functions
    */

    function addContractFunds(uint value) private {
        contractFunds += value;
    }

    function removeContractFunds(uint value) private {
        // Transfer an amount from the contract balance to the operator.
        uint operatorContractBalance = getOperatorContractBalance();

        if(value > operatorContractBalance) {
            revert InsufficientFunds(operatorContractBalance, value);
        }

        // If the value is higher than the extra funds, subtract the difference from "contractFunds". This accounting makes it so extra funds are spent first.
        if(value > getExtraContractBalance()) {
            contractFunds -= (value - getExtraContractBalance());
        }
        sendToAddress(getOperatorAddress(), value);
    }

    function removeAllContractFunds() private {
        // Transfer the entire contract balance to the operator.
        contractFunds = 0;
        sendToAddress(getOperatorAddress(), getOperatorContractBalance());
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
        Utility Functions
    */

    function sendToAddress(address recipientAddress, uint value) private {
        // The caller is responsible for making sure that the address is actually payable.
        payable(recipientAddress).transfer(value);
    }

    /*
        External Functions
    */

    function action_fundContract() external payable {
        // The operator can call this to give gas to the contract.
        requireOperatorAddress(msg.sender);
        fundContract(msg.value);
    }

    function action_buyTickets() external payable {
        // Players can call this to buy tickets for the lottery.
        requireContractEnabled();
        requirePayableAddress(msg.sender);
        requirePlayerAddress(msg.sender);
        buyTickets(msg.sender, msg.value);
    }

    function action_endLottery() external {
        // The operator can call this to end the lottery and distribute the prize to the winner.
        requireOperatorAddress(msg.sender);
        endLottery();
    }

    function action_setContractEnabled(bool isEnabled) external {
        // The operator can call this to enable or disable the ability for players to enter the lottery.
        requireOperatorAddress(msg.sender);
        setContractEnabled(isEnabled);
    }

    function action_removeContractFunds(uint value) external {
        // The operator can call this to disable the ability for players to enter the lottery.
        requireOperatorAddress(msg.sender);
        removeContractFunds(value);
    }

    function action_removeAllContractFunds() external {
        // The operator can call this to disable the ability for players to enter the lottery.
        requireOperatorAddress(msg.sender);
        removeAllContractFunds();
    }

    function action_setOperatorAddress(address newOperatorAddress) external {
        // The current operator can assign the operator role to a new address.
        requireOperatorAddress(msg.sender);
        setOperatorAddress(newOperatorAddress);
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

    function query_getContractEnabled() external view returns (bool) {
        return getContractEnabled();
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
}