// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.12 <0.9.0;

import "@openzeppelin/contracts/utils/Strings.sol";

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

    /// The calling address is not payable.
    error NotPayable();

    /// This contract does not have the funds requested.
    error InsufficientFunds(uint contractBalance, uint requestedAmount);

    // Global switch to turn the lottery on and off.
    bool private isContractEnabled;

    // The operator owns this contract and is responsible for running the lottery. They must fund this contract with gas, and in return they will receive a cut of each prize.
    address private constant operatorAddress = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;

    // An integer between 0 and 100 representing the percentage of the "playerPrizePool" amount that the operator takes every game.
    // Note that the player always receives the entire "bonusPrizePool" amount.
    uint constant private operatorCut = 10;

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
    uint private ticketPrice = 1e16; // 0.01 ETH
    mapping(uint => address) private map_ticket2Address;
    mapping(address => uint) private map_address2NumTickets;

    /*
        Standard Contract Functions
    */

    constructor() payable {
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

    function fundContract() external payable {
        // The operator can call this to give gas to the contract.
        requireOperator(msg.sender);
        addContractFunds(msg.value);
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

        map_address2NumTickets[playerAddress] += numTickets;
        for(uint i = 0; i < numTickets; i++) {
            map_ticket2Address[currentTicketNumber++] = playerAddress;
        }

        sendToAddress(playerAddress, value);
    }

    function endLottery() external {
        address winningAddress;
        uint numTickets = currentTicketNumber;

        if(numTickets == 0) {
            // No one played, so just do nothing.
        }
        else if(isOnePlayer()) {
            // Since only one person has played, just give them the entire prize.
            winningAddress = map_ticket2Address[0];

            uint winnerPrize = bonusPrizePool + playerPrizePool;

            playerPrizePool = 0;
            bonusPrizePool = 0;
            sendToAddress(winningAddress, winnerPrize);
        }
        else {
            // Give the lottery operator their cut of the pot, and then give the rest to a randomly chosen winner.
            uint winningTicket = chooseWinningTicket(numTickets);
            winningAddress = map_ticket2Address[winningTicket];
            
            uint operatorPrize = playerPrizePool * operatorCut / 100;
            uint winnerPrize = playerPrizePool + bonusPrizePool - operatorPrize;

            playerPrizePool = 0;
            bonusPrizePool = 0;
            sendToAddress(getOperatorAddress(), operatorPrize);
            sendToAddress(winningAddress, winnerPrize);
        }
    }

    function isOnePlayer() private view returns (bool) {
        // Check to see if there is only one player who has purchased all the tickets.
        // We assume there is at least one ticket.
        address firstPlayer = map_ticket2Address[0];
        return totalAddressTickets(firstPlayer) == totalTickets();
    }

    function chooseWinningTicket(uint numTickets) private view returns (uint) {
        // This should only be called if at least two different players have purchased tickets.
        uint winningTicket = randomInt(numTickets);
        return winningTicket;
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

    function getContractEnabled() public view returns (bool) {
        return isContractEnabled;
    }

    function enableContract() external {
        // Enable the ability for players to enter the lottery.
        isContractEnabled = true;
    }

    function disableContract() external {
        // Disable the ability for players to enter the lottery.
        isContractEnabled = false;
    }

    function requireContractEnabled() view private {
        if(!getContractEnabled()) {
            revert ContractDisabled();
        }
    }

    function getOperatorAddress() public pure returns (address) {
        return operatorAddress;
    }

    function isOperatorAddress(address sender) public pure returns (bool) {
        return sender == getOperatorAddress();
    }

    function requireOperator(address sender) pure private {
        if(!isOperatorAddress(sender)) {
            revert NotOperator();
        }
    }

    /*
        Funding Functions
    */

    function getContractFunds() external view returns (uint) {
        return contractFunds;
    }

    function addContractFunds(uint value) public {
        contractFunds += value;
    }

    function getContractBalance() public view returns (uint) {
        // This is the true contract balance. This includes everything, including player funds.
        return address(this).balance;
    }

    function getAccountedContractBalance() public view returns (uint) {
        return contractFunds + playerPrizePool + bonusPrizePool;
    }

    function getExtraContractBalance() public view returns (uint) {
        // Returns the amount of "extra" funds this contract has. This should usually be zero, but may be more if funds are sent here in ways that cannot be accounted for.
        // For example, a coinbase transaction or another contract calling "selfdestruct" could send funds here without passing through the "receive" function for proper accounting.
        assert(getContractBalance() >= getAccountedContractBalance());
        return getContractBalance() - getAccountedContractBalance();
    }

    function getOperatorContractBalance() public view returns (uint) {
        // This is the balance that the operator has access to.
        return contractFunds + getExtraContractBalance();
    }

    function removeContractFunds(uint amount) public {
        // Transfer an amount from the contract balance to the operator.
        uint operatorContractBalance = getOperatorContractBalance();

        if(amount > operatorContractBalance) {
            revert InsufficientFunds(operatorContractBalance, amount);
        }

        // If the amount is higher than the extra funds, subtract the difference from "contractFunds". This accounting makes it so extra funds are spent first.
        if(amount > getExtraContractBalance()) {
            contractFunds -= (amount - getExtraContractBalance());
        }
        sendToAddress(getOperatorAddress(), amount);
    }

    function removeAllContractFunds() public {
        // Transfer the entire contract balance to the operator.
        contractFunds = 0;
        sendToAddress(getOperatorAddress(), getOperatorContractBalance());
    }

    function getPlayerPrizePool() public view returns (uint) {
        return playerPrizePool;
    }

    function addPlayerPrizePool(uint value) public {
        // Add funds to the bonus prize pool.
        bonusPrizePool += value;
    }

    function getBonusPrizePool() public view returns (uint) {
        return bonusPrizePool;
    }

    function addBonusPrizePool(uint value) public {
        // Add funds to the bonus prize pool.
        bonusPrizePool += value;
    }

    /*
        Query Functions
    */

    function isAddressPlaying(address playerAddress) public view returns (bool) {
        return map_address2NumTickets[playerAddress] > 0;
    }

    function totalAddressTickets(address playerAddress) public view returns (uint) {
        return map_address2NumTickets[playerAddress];
    }

    function totalTickets() public view returns (uint) {
        return currentTicketNumber;
    }

    function addressWinChanceString(address playerAddress) public view returns (string memory) {
        // Returns the probability that this address will win as a truncated decimal between 0 and 100.
        // Since solidity only supports integers, we must use extra steps to present a decimal.
        if(totalTickets() == 0) {
            return "";
        }
        uint numDecimalPlaces = 4;
        uint numerator = totalAddressTickets(playerAddress) * 100;
        uint denominator = totalTickets();

        uint chance_front = numerator / denominator;
        uint chance_mod = (numerator % denominator) * (10 ** numDecimalPlaces);
        uint chance_back = chance_mod / denominator;

        return string.concat(Strings.toString(chance_front), ".", Strings.toString(chance_back), "%");
    }

    /*
        Utility Functions
    */

    function sendToAddress(address recipientAddress, uint value) private {
        // The caller is responsible for making sure that the address is actually payable.
        payable(recipientAddress).transfer(value);
    }

    function isPayableAddress(address testAddress) private returns (bool) {
        // If the address is payable, this transfer should succeed.
        return payable(testAddress).send(0);
    }

    function requirePayableAddress(address testAddress) private {
        if(isPayableAddress(testAddress)) {
            revert NotPayable();
        }
    }
}