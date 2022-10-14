// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.12 <0.9.0;

import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Lottery
 * @dev A blockchain lottery
 * @custom:dev-run-script ./scripts/deploy_with_ethers.ts
 */
contract Lottery {
    // Global switch to turn the lottery on and off.
    bool isContractEnabled;

    // The operator owns this contract and is responsible for running the lottery. They must fund this contract with gas, and in return they will receive a cut of each prize.
    //address payable constant operatorAddress = payable(0x1761DF124EC3bADb17Ef3B02167D068f3E542aC9);
    address payable constant operatorAddress = payable(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);

    // The zero address can never play since it has no owner. We just use it for cases where there are no valid players.
    address payable constant zeroAddress = payable(0x0000000000000000000000000000000000000000);

    // An integer between 0 and 100 representing the percentage of the "playerPrizePool" amount that the operator takes every game.
    // Note that the player always receives the entire "bonusPrizePool" amount.
    uint constant operatorCut = 10;

    /* To ensure the safety of player money, the contract balance is accounted for by splitting it into three different places:
        // contractFunds - The money used to pay for gas. The operator can add or remove money at will.
        // playerPrizePool - The money players have paid to purchase tickets. The operator gets a cut of each prize automatically, but otherwise they cannot add or remove funds.
        // bonusPrizePool - The money that the operator has optionally added to "sweeten the pot" and provide more prize money. The operator can add funds but cannot remove them.
    */
    uint contractFunds;
    uint playerPrizePool;
    uint bonusPrizePool;

    // Variables to keep track of who is playing and how many tickets they have.
    //mapping(address => bool) public map_isPlaying;
    //address payable[] public list_playerAddress;

    uint currentTicketNumber;
    uint ticketPrice = 100000000;
    mapping(uint => address payable) public map_ticket2Address;
    mapping(address => uint) public map_address2NumTickets;

    /*
        Standard Contract Functions
    */

    constructor() payable {
        // When deploying this contract, initial funds should be paid to allow for smooth lottery operation.
        isContractEnabled = true;
    }

    receive() external payable {
        // If a player sends money, then give them tickets. If the operator sends money, then add it to the contract funds.
        address payable sender = payable(msg.sender);
        uint value = msg.value;

        if(sender == operatorAddress) {
            contractFunds += value;
        }
        else {
            requireContractEnabled();

            // Each ticket has a fixed cost. After spending all the funds on tickets, anything left over will be given back to the player.
            uint numTickets = value / ticketPrice;
            playerPrizePool += numTickets * ticketPrice;

            map_address2NumTickets[sender] += numTickets;

            for(uint i = 0; i < numTickets; i++) {
                map_ticket2Address[currentTicketNumber++] = sender;
            }

            // TODO send leftover funds back.

            //fundLottery() // Can we call this without paying again?
        }
    }

    /*
        Lottery Functions
    */

    function chooseWinningAddress() public view returns (address payable) {
        uint numPlayers = currentTicketNumber;
        uint winningTicket;

        // If less than 2 people are playing, deal with these cases manually.
        if(numPlayers == 0) {
            // There is no winner, so just return the zero address.
            return zeroAddress;
        }
        else if(numPlayers == 1) {
            // Don't bother generating a random number. It's a waste of gas and/or time in this case.
            winningTicket = 0;
        }
        else {
            // Randomly pick a winner from all the player addresses. Each address should have an equal chance of winning.
            winningTicket = randomInt(numPlayers);
        }

        return map_ticket2Address[winningTicket];
    }

    function endLottery() public {
        address payable winningAddress = chooseWinningAddress();
        if(winningAddress == zeroAddress) {
            // No one played, so just do nothing.
        }
        else {
            // Give the lottery operator their cut of the pot, and then give the rest to the winner.
            uint operatorPrize = playerPrizePool * operatorCut / 100;
            uint winnerPrize = bonusPrizePool + playerPrizePool - operatorPrize;
            playerPrizePool = 0;
            bonusPrizePool = 0;
            operatorAddress.transfer(operatorPrize);
            winningAddress.transfer(winnerPrize);
        }
    }

    /*
        RNG Functions
    */

    function randomInt(uint N) public view returns (uint) {
        // Generate a random integer 0 <= n < L.
        uint randomHash = uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp)));
        return randomHash % N;
    }

    /*
        Control Functions
    */

    function enableContract() public {
        // Enable the ability for players to enter the lottery.
        isContractEnabled = true;
    }

    function disableContract() public {
        // Disable the ability for players to enter the lottery.
        isContractEnabled = false;
    }

    function requireContractEnabled() public view {
        require(isContractEnabled, "This contract is currently disabled.");
    }

    /*
        Funding Functions
    */

    function getContractFunds() external view returns (uint) {
        return contractFunds;
    }

    function addContractFunds() external payable {
        // Directly fund the contract. This does not add to the prize or enter any addresses into the lottery.
        // This should only be called by the lottery operator to give the contract gas.
        contractFunds += msg.value;
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
        require(amount <= operatorContractBalance, string.concat("The amount ", Strings.toString(amount), " is greater than the contract balance ", Strings.toString(operatorContractBalance)));

        // Any extra funds should be taken into account first, then subtract from "contractFunds".
        contractFunds -= (amount - getExtraContractBalance());
        operatorAddress.transfer(amount);
    }

    function removeAllContractFunds() public {
        // Transfer the entire contract balance to the operator.
        contractFunds = 0;
        operatorAddress.transfer(getOperatorContractBalance());
    }

    function getPlayerPrizePool() external view returns (uint) {
        return playerPrizePool;
    }

/*
    function fundLottery() external payable {
        // When addresses pay the contract, they are entered into the lottery.
        // If they sent too much, return the excess amount.
        // If they have already entered the lottery, error so the transfer can be reverted.
        requireContractEnabled();

        playerPrizePool += msg.value;
        registerAddress(payable(msg.sender));
    }
*/

    function getBonusPrizePool() external view returns (uint) {
        return bonusPrizePool;
    }

    function addBonusPrizePool() external payable {
        // Add funds to the bonus prize pool.
        bonusPrizePool += msg.value;
    }

    /*
        Query Functions
    */

    function isAddressPlaying(address payable playerAddress) public view returns (bool) {
        return map_address2NumTickets[playerAddress] > 0;
    }

    function totalAddressTickets(address payable playerAddress) public view returns (uint) {
        return map_address2NumTickets[playerAddress];
    }

    function totalTickets() public view returns (uint) {
        return currentTicketNumber;
    }

    function addressWinChanceString(address payable playerAddress) public view returns (string memory) {
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

    /*
    function toString(address account) public pure returns(string memory) {
        return toString(abi.encodePacked(account));
    }

    function toString(uint256 value) public pure returns(string memory) {
        return toString(abi.encodePacked(value));
    }

    function toString(bytes32 value) public pure returns(string memory) {
        return toString(abi.encodePacked(value));
    }

    function toString(bytes memory data) public pure returns(string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < data.length; i++) {
            str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
            str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
    */
}