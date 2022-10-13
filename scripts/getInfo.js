const { ethers } = require("hardhat");

async function deployContract() {
    // Create factory that will deploy the contract.
    const lotteryFactory = await ethers.getContractFactory("Lottery");

    // Deploy the contract to a random address.
    const lotteryContract = await lotteryFactory.deploy();
    await lotteryContract.deployed();

    // Access address.
    const lotteryAddress = lotteryContract.address;
    console.log('Lottery deployed at: '+ lotteryAddress);
    return lotteryAddress;
}

async function async_getInfo() {
    console.log('Start');
    let lotteryAddress = await deployContract();
    console.log('Lottery deployed at: '+ lotteryAddress);
    console.log('End');
}

async_getInfo();