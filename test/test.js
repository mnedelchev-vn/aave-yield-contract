const {expect} = require("chai");
const {ethers} = require("hardhat");

describe("YieldContract", function () {
    it("Should return the new greeting once it's changed", async function () {
        const [signer] = await ethers.getSigners();
        console.log('Tester balance at the START of the test: ' + ethers.utils.formatEther(await signer.getBalance()) + ' ETH.');

        const YieldContractFactory = await ethers.getContractFactory('YieldContract');
        const YieldContract = await YieldContractFactory.deploy();
        await YieldContract.deployed();

        console.log('YieldContract deployed at: ' + YieldContract.address);
        console.log('YieldContract deploying costed: ' + ethers.utils.formatEther(YieldContract.deployTransaction.gasPrice) * YieldContract.deployTransaction.gasLimit + ' ETH.');

        // depositing 0.0005 ETH
        var userInitialDeposit = 500000000000000;
        await YieldContract.buyAndDeposit({
            value: userInitialDeposit
        });
        console.log('Wallet address ' + signer.address + ' successfully deposited ' + ethers.utils.formatEther(userInitialDeposit) + ' ETH.');
        console.log('Total Aave USDC deposit of Wallet address ' + signer.address + ': ' + parseInt(await YieldContract.depositors(signer.address)) + ' USDC.');

        // depositing 0.0003 ETH
        var userSecondDeposit = 300000000000000;
        await YieldContract.buyAndDeposit({
            value: userSecondDeposit
        });
        console.log('Wallet address ' + signer.address + ' successfully deposited ' + ethers.utils.formatEther(userSecondDeposit) + ' ETH.');
        console.log('Total Aave USDC deposit of Wallet address ' + signer.address + ': ' + parseInt(await YieldContract.depositors(signer.address)) + ' USDC.');

        // withdrawing half of the USDC deposit
        const halfOfUSDCAmount = parseInt(await YieldContract.depositors(signer.address) / 2);
        await YieldContract['withdraw(uint256)'](halfOfUSDCAmount);
        console.log('Wallet address ' + signer.address + ' successfully withdrawn ' + halfOfUSDCAmount + ' USDC.');
        console.log('Total Aave USDC deposit of Wallet address ' + signer.address + ': ' + parseInt(await YieldContract.depositors(signer.address)) + ' USDC.');

        // depositing 0.0004 ETH
        var userThirdDeposit = 400000000000000;
        await YieldContract.buyAndDeposit({
            value: userThirdDeposit
        });
        console.log('Wallet address ' + signer.address + ' successfully deposited ' + ethers.utils.formatEther(userThirdDeposit) + ' ETH.');
        console.log('Total Aave USDC deposit of Wallet address ' + signer.address + ': ' + parseInt(await YieldContract.depositors(signer.address)) + ' USDC.');

        // withdrawing everything left of the USDC deposit
        await YieldContract['withdraw()']();
        console.log('Wallet address ' + signer.address + ' successfully withdrawn all of the USDC.');
        console.log('Total Aave USDC deposit of Wallet address ' + signer.address + ': ' + parseInt(await YieldContract.depositors(signer.address)) + ' USDC.');

        console.log('Tester balance at the END of the test: ' + ethers.utils.formatEther(await signer.getBalance()) + ' ETH.');
    });
});