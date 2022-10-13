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

async function async_changeValue() {
    // Deploy contract and then use address to access contract object.
    let lotteryAddress = await deployContract();
    const lotteryContract = await ethers.getContractAt("Lottery", lotteryAddress);

    // Call the store function on the contract and wait for it to finish.
    const call_store = await lotteryContract.store(777);
    await call_store.wait();

    // Call the retrieve function on the contract to get the value we stored previously.
    let value = (await lotteryContract.retrieve()).toNumber();
    console.log('Value: ' + value);
}

async_changeValue();