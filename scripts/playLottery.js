const { ethers } = require("hardhat");


function handleError(err) {
    console.log('ERROR:');
    console.log(JSON.stringify(err, Object.getOwnPropertyNames(err), 4));
}

async function deployContract(startingBalance, args) {
    // Create factory that will deploy the contract.
    const lotteryFactory = await ethers.getContractFactory("MusicslayerLottery");

    // Deploy the contract to a random address.
    //const lotteryContract = await lotteryFactory.deploy("0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2", { value: ethers.utils.parseEther(startingBalance) });
    //const lotteryContract = await lotteryFactory.deploy(10000000000, 5, { value: ethers.utils.parseEther(startingBalance) });
    const lotteryContract = await lotteryFactory.deploy(...args, { value: startingBalance });
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

async function fundLottery(lotteryContract, amount) {
    const call_fundLottery = await lotteryContract.fundLottery({ value: ethers.utils.parseEther(amount) });
    await call_fundLottery.wait();
}

async function fundContract(lotteryContract, amount) {
    const call_fundContract = await lotteryContract.fundContract({ value: ethers.utils.parseEther(amount) });
    await call_fundContract.wait();
}

async function endLottery(lotteryContract) {
    console.log('X');

    const call_endLottery = await lotteryContract.endLottery();

    console.log('Y');

    return call_endLottery;
}

async function getContractEnabled(lotteryContract) {
    const call_getContractEnabled = await lotteryContract.getContractEnabled();
    return call_getContractEnabled;
}

async function enableContract(lotteryContract) {
    const call_enableContract = await lotteryContract.enableContract();
    return call_enableContract.wait();
}

async function disableContract(lotteryContract) {
    const call_disableContract = await lotteryContract.disableContract();
    return call_disableContract.wait();
}

async function requireContractEnabled(lotteryContract) {
    const call_requireContractEnabled = await lotteryContract.requireContractEnabled();
    return call_requireContractEnabled.wait();
}

async function getBalance(lotteryContract) {
    const call_getBalance = await lotteryContract.getBalance();
    return call_getBalance;
}

async function removeContractFunds(lotteryContract) {
    //const call_removeContractFunds = await lotteryContract.removeContractFunds(ethers.utils.parseEther(amount));
    const call_removeContractFunds = await lotteryContract.foo();
    await call_removeContractFunds.wait();
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

/*
async function async_playLottery() {
    // Deploy contract and then use address to access contract object.
    let lotteryAddress = await deployContract("0.000001");
    const lotteryContract = await ethers.getContractAt("Lottery", lotteryAddress);

    //pA1 = "0xc0ffee254729296a45a3885639AC7E10F9d54979";
    pA1 = "0xdD870fA1b7C4700F2BD7f44238821C26f7392148";
    //pA2 = "0x999999cf1046e68e36E1aA2E0E07105eDDD1f08E";

    await registerAddress(lotteryContract, pA1);
    //await registerAddress(lotteryContract, pA2);

    console.log('Winner: ' + await chooseWinningAddress(lotteryContract));

    await fundLottery(lotteryContract, "0.00000000723");

    await fundContract(lotteryContract, "0.00002");

    console.log('Balance Before: ' + await getBalance(lotteryContract));

    await endLottery(lotteryContract);

    console.log('Balance After: ' + await getBalance(lotteryContract));
}
*/

/*
async function async_playLottery() {
    // Deploy contract and then use address to access contract object.
    let lotteryAddress = await deployContract("0.000001");
    const lotteryContract = await ethers.getContractAt("Lottery", lotteryAddress);

    console.log('enabled? ' + await getContractEnabled(lotteryContract));
    await disableContract(lotteryContract);
    console.log('enabled? ' + await getContractEnabled(lotteryContract));
    await requireContractEnabled(lotteryContract);
}
*/

/*
async function async_playLottery() {
    // Test Fallback Function
    let lotteryAddress = await deployContract("0.00000000000001");
    const lotteryContract = await ethers.getContractAt("Lottery", lotteryAddress);

    const nonExistentFuncSignature = 'nonExistentFunction(uint256,uint256)';

    [deployer] = await ethers.getSigners();
    const fakeLotteryContract = new ethers.Contract(
        lotteryContract.address,
        [
            ...lotteryContract.interface.fragments,
            `function ${nonExistentFuncSignature}`,
        ],
        deployer,
    );

    console.log('X');
    const call_foo = await fakeLotteryContract.nonExistentFunction(0, 0);
    await call_foo.wait();
    console.log('Y');
}
*/

async function async_playLottery() {
    // Deploy contract and then use address to access contract object.
    let lotteryAddress = await deployContract(ethers.utils.parseEther("0.00000000000001"), [5, ethers.utils.parseEther("0.01")]);
    const lotteryContract = await ethers.getContractAt("MusicslayerLottery", lotteryAddress);

    console.log('X');
    //const call_foo = await lotteryContract.removeContractFunds(50000000000);
    const call_foo = await lotteryContract.removeContractFunds(5000);
    await call_foo.wait();
    console.log('Y');
}

async_playLottery().catch(handleError);