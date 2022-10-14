const { ethers } = require("hardhat");

function handleError(err) {
    console.log('ERROR:');
    console.log(JSON.stringify(err, ["message", "arguments", "type", "name"]));
}

async function deployContract(startingBalance) {
    // Create factory that will deploy the contract.
    const lotteryFactory = await ethers.getContractFactory("Lottery");

    // Deploy the contract to a random address.
    const lotteryContract = await lotteryFactory.deploy({ value: ethers.utils.parseEther(startingBalance) });
    await lotteryContract.deployed();

    // Access address.
    const lotteryAddress = lotteryContract.address;
    console.log('Lottery deployed at: '+ lotteryAddress);
    return lotteryAddress;
}

async function registerAddress(lotteryContract, playerAddress) {
    const call_registerAddress = await lotteryContract.registerAddress(playerAddress);
    await call_registerAddress.wait();
}

async function isAddressPlaying(lotteryContract, playerAddress) {
    const call_isAddressPlaying = await lotteryContract.isAddressPlaying(playerAddress);
    return call_isAddressPlaying;
}

async function chooseWinningAddress(lotteryContract) {
    const call_chooseWinningAddress = await lotteryContract.chooseWinningAddress();
    return call_chooseWinningAddress;
}

async function fund(lotteryContract, amount) {
    //const call_fund = await lotteryContract.fund(amount);
    //await call_fund.wait();

    //const call_receive = await lotteryContract.receive();
    //await call_receive.wait();

    //const call_fund = await lotteryContract.fund({ value: amount });
    const call_fund = await lotteryContract.fund({ value: ethers.utils.parseEther(amount) });
    await call_fund.wait();
}

async function getBalance(lotteryContract) {
    const call_getBalance = await lotteryContract.getBalance();
    return call_getBalance;
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
    startingBalance = "0.000001";
    let lotteryAddress = await deployContract(startingBalance);
    const lotteryContract = await ethers.getContractAt("Lottery", lotteryAddress);

    pA1 = "0xc0ffee254729296a45a3885639AC7E10F9d54979";
    pA2 = "0x999999cf1046e68e36E1aA2E0E07105eDDD1f08E";

    //await registerAddress(lotteryContract, pA1);
    //await registerAddress(lotteryContract, pA2);

    console.log('Winner: ' + await chooseWinningAddress(lotteryContract));

    await fund(lotteryContract, "0.00000000723");

    console.log('Balance: ' + await getBalance(lotteryContract));
}

async_playLottery().catch(handleError);