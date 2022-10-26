const { ethers } = require("hardhat");

async function deployContract(startingBalance, args) {
    // Create factory that will deploy the contract.
    const lotteryFactory = await ethers.getContractFactory("MusicslayerLottery");

    // Deploy the contract to a random address.
    const lotteryContract = await lotteryFactory.deploy(...args, { value: startingBalance });
    await lotteryContract.deployed();

    // Access address.
    const lotteryAddress = lotteryContract.address;
    console.log('Lottery deployed at: '+ lotteryAddress);
    return lotteryAddress;
}

async function async_getInfo() {
    console.log('Start');

    let lotteryAddress = await deployContract(ethers.utils.parseEther("0.00000000000001"), [5, ethers.utils.parseEther("0.01")]);
    const lotteryContract = await ethers.getContractAt("MusicslayerLottery", lotteryAddress);

    const call_foo = await lotteryContract.get_addressClaimableBalance("0xb15b75994a040E63Eb961d8c3D26cB0A4e9D5E49");
    await call_foo.wait();

    console.log('End');
}

async_getInfo();