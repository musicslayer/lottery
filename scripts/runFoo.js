const { ethers } = require("hardhat");

function handleError(err) {
    console.log('ERROR:');
    console.log(JSON.stringify(err, Object.getOwnPropertyNames(err), 4));
}

async function async_runFoo() {
    const fooFactory = await ethers.getContractFactory("Foo");
    const fooContract = await fooFactory.deploy();
    await fooContract.deployed();

    const call_foo = await fooContract.foo();
    await call_foo.wait();
}

async_runFoo().catch(handleError);