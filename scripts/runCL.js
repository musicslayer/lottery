const { ethers } = require("hardhat");

function handleError(err) {
    console.log('ERROR:');
    console.log(JSON.stringify(err, Object.getOwnPropertyNames(err), 4));
}

async function async_runCL() {
    const clFactory = await ethers.getContractFactory("CL");
    const clContract = await clFactory.deploy();
    await clContract.deployed();

    console.log("X");

    const call_clTest = await clContract.clTest();
    await call_clTest.wait();
    //console.log(call_foo);

    console.log("Y");
}

async_runCL().catch(handleError);