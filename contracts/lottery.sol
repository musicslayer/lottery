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

    address payable constant zeroAddress = payable(0x0000000000000000000000000000000000000000);
    //address payable constant operatorAddress = payable(0x1761DF124EC3bADb17Ef3B02167D068f3E542aC9);
    address payable constant operatorAddress = payable(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
    uint constant operatorCut = 10; // int between 0 and 100 representing the percentage of the pot that the operator takes every game.

    uint totalPrize;

    mapping(address => bool) public map_isPlaying;
    address payable[] public list_playerAddress;

    constructor() payable {
        isContractEnabled = true;
    }

    function requireContractEnabled() public view {
        require(isContractEnabled, "This contract is currently disabled.");
    }

    function fundLottery() external payable {
        // When addresses pay the contract, they are entered into the lottery.
        // If they sent too much, return the excess amount.
        // If they have already entered the lottery, error so the transfer can be reverted.
        requireContractEnabled();

        totalPrize += msg.value;
        registerAddress(payable(msg.sender));
    }

    function registerAddress(address payable playerAddress) public {
        // If address is already playing, we need to error. An address can only enter the lottery once.
        bool isPlaying = map_isPlaying[playerAddress];
        require(!isPlaying, "This address has already entered the lottery.");

        // Register this address as a player in the lottery.
        map_isPlaying[playerAddress] = true;
        list_playerAddress.push(playerAddress);
    }
    
    function isAddressPlaying(address payable playerAddress) public view returns (bool) {
        requireContractEnabled();
        return map_isPlaying[playerAddress];
    }

    function chooseWinningAddress() public view returns (address payable) {
        uint numPlayers = list_playerAddress.length;
        uint winner;

        // If less than 2 people are playing, deal with these cases manually.
        if(numPlayers == 0) {
            // There is no winner, so just return the zero address.
            return zeroAddress;
        }
        else if(numPlayers == 1) {
            // Don't bother generating a random number. It's a waste of gas and/or time in this case.
            winner = 0;
        }
        else {
            // Randomly pick a winner from all the player addresses. Each address should have an equal chance of winning.
            winner = randomInt(numPlayers);
        }

        return list_playerAddress[winner];
    }

    function endLottery() public {
        address payable winningAddress = chooseWinningAddress();
        if(winningAddress == zeroAddress) {
            // No one played, so just do nothing.
        }
        else {
            // Give the lottery operator their cut of the pot, and then give the rest to the winner.
            uint operatorPrize = totalPrize * operatorCut / 100;
            uint winnerPrize = totalPrize - operatorPrize;
            totalPrize = 0;
            operatorAddress.transfer(operatorPrize);
            winningAddress.transfer(winnerPrize);
        }
    }

    function fundContract() external payable {
        // Directly fund the contract. This does not add to the prize or enter any addresses into the lottery.
        // This should only be called by the lottery operator to give the contract gas.
    }

    function withdrawAll() public {
        // Transfer the entire contract balance to the operator.
        operatorAddress.transfer(getBalance());
    }

    function withdraw(uint amount) public {
        // Transfer an amount from the contract balance to the operator.
        uint balance = getBalance();
        require(amount <= balance, string.concat("The amount ", Strings.toString(amount), " is greater than the contract balance ", Strings.toString(balance)));
        operatorAddress.transfer(amount);
    }

    function getPrize() public view returns (uint) {
        return totalPrize;
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function randomInt(uint N) public view returns (uint) {
        // Generate a random integer 0 <= n < L.
        uint randomHash = uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp)));
        return randomHash % N;
    }

    function enableContract() public {
        // Enable the ability for players to enter the lottery.
        isContractEnabled = true;
    }

    function disableContract() public {
        // Disable the ability for players to enter the lottery.
        isContractEnabled = false;
    }

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