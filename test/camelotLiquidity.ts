import { ethers } from "hardhat";
import { expect } from "chai";

import * as Contracts from "../typechain-types";
import { BaseContract, Signer } from "ethers";

describe("camelot liquidity contract test", function () {
    let admin: Signer;
    let camelotLiquidityContract: Contracts.CamelotLiquidity;
    let usdc: Contracts.IERC20;
    let usdce: Contracts.IERC20;
    let wsteth: Contracts.IERC20;
    let weth: Contracts.IERC20;

    const nonfungiblePositionManager = "0x00c7f3082833e796A5b3e4Bd59f6642FF44DCD15"; 

    const usdcAddress = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
    const usdceAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
    const usdcusdcePoolAddressPool = "0xc86Eb7B85807020b4548EE05B54bfC956eEbbfCD"; 

    const wstethAddress = "0x5979D7b546E38E414F7E9822514be443A4800529";
    const wethAddress = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
    const wstethwethPoolAddressPool = "0xdEb89DE4bb6ecf5BFeD581EB049308b52d9b2Da7"; 
    
    async function deployCamelotLiquidity() {
        const camelotLiquidity = await ethers.getContractFactory("CamelotLiquidity");
        camelotLiquidityContract = await camelotLiquidity.deploy(nonfungiblePositionManager, usdcusdcePoolAddressPool);
        await camelotLiquidityContract.waitForDeployment();

        console.log("deploy CamelotLiquidity successfully: %s", await camelotLiquidityContract.getAddress());
    }

    before(async function () {
        usdc = await ethers.getContractAt("IERC20", usdcAddress);
        usdce = await ethers.getContractAt("IERC20", usdceAddress);

        wsteth = await ethers.getContractAt("IERC20", wstethAddress);
        weth = await ethers.getContractAt("IERC20", wethAddress);

        [admin] = await ethers.getSigners();
        await deployCamelotLiquidity();
    });

    it.skip("mint position usdc_usdce pool, should create position successfully on camelot dex", async function () {
        // const tx = await admin.sendTransaction({
        //     to: "0x84e66f86c28502c0fc8613e1d9cbbed806f7adb4",
        //     value: ethers.parseEther("0.5")
        // });

        const usdcSigner = await ethers.getImpersonatedSigner("0x463f5d63e5a5edb8615b0e485a090a18aba08578");
        const transferTx0 = await usdc.connect(usdcSigner).transfer(admin, ethers.parseUnits("10", 6));
        await transferTx0.wait();
        console.log("balance of admin : %s usdc", await usdc.connect(admin).balanceOf(admin));

        const usdceSigner = await ethers.getImpersonatedSigner("0xb874005cbea25c357b31c62145b3aef219d105cf");
        const transferTx1 = await usdce.connect(usdceSigner).transfer(admin, ethers.parseUnits("10", 6));
        await transferTx1.wait();
        console.log("balance of admin : %s usdce", await usdce.connect(admin).balanceOf(admin));

        const usdcPoolBalance = await usdc.connect(admin).balanceOf(usdcusdcePoolAddressPool);
        const usdcePoolBalance = await usdce.connect(admin).balanceOf(usdcusdcePoolAddressPool);
        console.log("balance of pool before mint position: %s usd, %s usdce", usdcPoolBalance, usdcePoolBalance);

        const usdcAmount = ethers.parseUnits("10", 6);
        const usdceAmount = ethers.parseUnits("10", 6);

        await usdc.connect(admin).approve(await camelotLiquidityContract.getAddress(), usdcAmount);
        await usdce.connect(admin).approve(await camelotLiquidityContract.getAddress(), usdceAmount);

        const transferTx3 = await camelotLiquidityContract.connect(admin).mintPosition(
            usdcAddress,
            usdcAmount,
            usdceAddress,
            usdceAmount
        );
        await transferTx3.wait();  

        const newUsdcPoolBalance = await usdc.connect(admin).balanceOf(usdcusdcePoolAddressPool);
        const newUsdcePoolBalance = await usdce.connect(admin).balanceOf(usdcusdcePoolAddressPool);
        console.log("balance of pool after mint position: %s usd, %s usdce", newUsdcPoolBalance , newUsdcePoolBalance);

        console.log("balance of admin before mint position: %s usd, %s usdce", 
            await usdc.connect(admin).balanceOf(admin), 
            await usdce.connect(admin).balanceOf(admin)
        );

        expect(newUsdcPoolBalance).to.greaterThan(usdcPoolBalance);
        expect(newUsdcePoolBalance).to.greaterThan(usdcePoolBalance);
    });

    it.skip("mint position weth_wsteth pool, should create position successfully on camelot dex", async function () {
        const tx0 = await admin.sendTransaction({
            to: "0x916792f7734089470de27297903bed8a4630b26d",
            value: ethers.parseEther("0.5")
        });

        const tx1 = await admin.sendTransaction({
            to: "0x1eed63efba5f81d95bfe37d82c8e736b974f477b",
            value: ethers.parseEther("0.5")
        });

        const wstethSigner = await ethers.getImpersonatedSigner("0x916792f7734089470de27297903bed8a4630b26d");
        const transferTx0 = await wsteth.connect(wstethSigner).transfer(admin, ethers.parseEther("10"));
        await transferTx0.wait();
        console.log("balance of admin : %s wsteth", await wsteth.connect(admin).balanceOf(admin));

        const wethSigner = await ethers.getImpersonatedSigner("0x1eed63efba5f81d95bfe37d82c8e736b974f477b");
        const transferTx1 = await weth.connect(wethSigner).transfer(admin, ethers.parseEther("10"));
        await transferTx1.wait();
        console.log("balance of admin : %s weth", await weth.connect(admin).balanceOf(admin));

        const wstethPoolBalance = await wsteth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        const wstPoolBalance = await weth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        console.log("balance of pool before mint position: %s wsteth, %s weth", wstethPoolBalance, wstPoolBalance);

        const wstethAmount = ethers.parseUnits("10", 18);
        const wethAmount = ethers.parseUnits("10", 18);

        await wsteth.connect(admin).approve(await camelotLiquidityContract.getAddress(), wstethAmount);
        await weth.connect(admin).approve(await camelotLiquidityContract.getAddress(), wethAmount);

        const transferTx3 = await camelotLiquidityContract.connect(admin).mintPosition(
            wstethAddress,
            wstethAmount,
            wethAddress,
            wethAmount
        );
        await transferTx3.wait();  

        const newWstethPoolBalance = await wsteth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        const newWethPoolBalance = await weth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        console.log("balance of pool after mint position: %s wsteth, %s weth", newWstethPoolBalance , newWethPoolBalance);

        console.log("balance of admin before mint position: %s wsteth, %s weth", 
            await wsteth.connect(admin).balanceOf(admin), 
            await weth.connect(admin).balanceOf(admin)
        );

        expect(newWstethPoolBalance).to.greaterThan(wstethPoolBalance);
        expect(newWethPoolBalance).to.greaterThan(wstPoolBalance);
    });

    it(", should create position successfully on camelot dex", async function () {
        const tx0 = await admin.sendTransaction({
            to: "0x916792f7734089470de27297903bed8a4630b26d",
            value: ethers.parseEther("0.5")
        });

        const tx1 = await admin.sendTransaction({
            to: "0x1eed63efba5f81d95bfe37d82c8e736b974f477b",
            value: ethers.parseEther("0.5")
        });

        const wstethSigner = await ethers.getImpersonatedSigner("0x916792f7734089470de27297903bed8a4630b26d");
        const transferTx0 = await wsteth.connect(wstethSigner).transfer(admin, ethers.parseEther("10"));
        await transferTx0.wait();
        console.log("balance of admin : %s wsteth", await wsteth.connect(admin).balanceOf(admin));

        const wethSigner = await ethers.getImpersonatedSigner("0x1eed63efba5f81d95bfe37d82c8e736b974f477b");
        const transferTx1 = await weth.connect(wethSigner).transfer(admin, ethers.parseEther("10"));
        await transferTx1.wait();
        console.log("balance of admin : %s weth", await weth.connect(admin).balanceOf(admin));

        const wstethPoolBalance = await wsteth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        const wstPoolBalance = await weth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        console.log("balance of pool before mint position: %s wsteth, %s weth", wstethPoolBalance, wstPoolBalance);

        const wstethAmount = ethers.parseUnits("10", 18);
        const wethAmount = ethers.parseUnits("10", 18);

        await wsteth.connect(admin).approve(await camelotLiquidityContract.getAddress(), wstethAmount);
        await weth.connect(admin).approve(await camelotLiquidityContract.getAddress(), wethAmount);

        const transferTx3 = await camelotLiquidityContract.connect(admin).mintPosition(
            wstethAddress,
            wstethAmount,
            wethAddress,
            wethAmount
        );
        await transferTx3.wait();  

        const newWstethPoolBalance = await wsteth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        const newWethPoolBalance = await weth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        console.log("balance of pool after mint position: %s wsteth, %s weth", newWstethPoolBalance , newWethPoolBalance);

        console.log("balance of admin before mint position: %s wsteth, %s weth", 
            await wsteth.connect(admin).balanceOf(admin), 
            await weth.connect(admin).balanceOf(admin)
        );

        expect(newWstethPoolBalance).to.greaterThan(wstethPoolBalance);
        expect(newWethPoolBalance).to.greaterThan(wstPoolBalance);
    });
});
