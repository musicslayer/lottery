const { ethers } = require("hardhat");

function handleError(err) {
    console.log('ERROR:');
    console.log(JSON.stringify(err, ["message", "arguments", "type", "name"]));
}

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

async function registerAddress(lotteryContract, playerAddress) {
    const call_registerAddress = await lotteryContract.registerAddress(playerAddress);
    await call_registerAddress.wait();

    console.log('Address registered: ' + playerAddress);
}

async function isAddressPlaying(lotteryContract, playerAddress) {
    const call_isAddressPlaying = await lotteryContract.isAddressPlaying(playerAddress);
    return call_isAddressPlaying;
}

async function chooseWinner(lotteryContract) {
    const call_chooseWinner = await lotteryContract.chooseWinner();
    return call_chooseWinner;
}

async function async_playLotteryDebug() {
    // Deploy contract and then use address to access contract object.
    let lotteryAddress = await deployContract();
    const lotteryContract = await ethers.getContractAt("Lottery", lotteryAddress);

    pA1 = "0xc0ffee254729296a45a3885639AC7E10F9d54979";
    pA2 = "0x999999cf1046e68e36E1aA2E0E07105eDDD1f08E";

    console.log('isPlaying: ' + await isAddressPlaying(lotteryContract, pA1));

    // Register an address
    await registerAddress(lotteryContract, pA1);

    console.log('isPlaying: ' + await isAddressPlaying(lotteryContract, pA1));
    
    // Register the same address again and error.
    try {
        await registerAddress(lotteryContract, pA1);
    }
    catch(err) {
        handleError(err);
    }

    // Register a different address.
    await registerAddress(lotteryContract, pA2);

    console.log('Winner: ' + await chooseWinner(lotteryContract));
}

async function async_playLottery() {
    // Deploy contract and then use address to access contract object.
    let lotteryAddress = await deployContract();
    const lotteryContract = await ethers.getContractAt("Lottery", lotteryAddress);

    pA1 = "0xc0ffee254729296a45a3885639AC7E10F9d54979";
    pA2 = "0x999999cf1046e68e36E1aA2E0E07105eDDD1f08E";

    //await registerAddress(lotteryContract, pA1);
    //await registerAddress(lotteryContract, pA2);

    console.log('Winner: ' + await chooseWinner(lotteryContract));
}

async_playLottery().catch(handleError);