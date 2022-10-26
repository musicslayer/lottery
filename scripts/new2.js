const { ethers } = require("hardhat");


function handleError(err) {
    console.log('ERROR:');
    console.log(JSON.stringify(err, Object.getOwnPropertyNames(err), 4));
}

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

async function async_foo() {
    // Deploy contract and then use address to access contract object.
    let lotteryAddress = await deployContract(ethers.utils.parseEther("0.00000000000001"), [5, ethers.utils.parseEther("0.01")]);
    //let lotteryAddress = "0x9d83e140330758a8fFD07F8Bd73e86ebcA8a5692";
    const lotteryContract = await ethers.getContractAt("MusicslayerLottery", lotteryAddress);

    //console.log('C');
    //console.log(lotteryContract);

    console.log('X');
    const call_buy = await lotteryContract.action_buyTickets();
    await call_buy.wait();
    console.log('Y');
}

async_foo().catch(handleError);