import { ethers } from "hardhat";
import { expect } from "chai";

import * as Contracts from "../typechain-types";
import { BaseContract, Signer, AbiCoder, ContractTransactionReceipt } from "ethers";

describe("camelot liquidity contract test", function () {
    let admin: Signer;
    let camelotLiquidityContract: Contracts.CamelotLiquidity;
    let usdc: Contracts.IERC20;
    let usdce: Contracts.IERC20;
    let wsteth: Contracts.IERC20;
    let weth: Contracts.IERC20;

    let nftPosition: Contracts.IERC721;

    let liquidityTokenId: number;
    let liquidityAmount: number;

    const LIQUIDITY_TOKEN_ID = 0;
    const LIQUIDITY_AMOUNT = 1;

    const nonfungiblePositionManager = "0x00c7f3082833e796A5b3e4Bd59f6642FF44DCD15"; 

    const nftPositionAddress = "0x00c7f3082833e796a5b3e4bd59f6642ff44dcd15";
    const usdcAddress = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";
    const usdceAddress = "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8";
    const usdcusdcePoolAddressPool = "0xc86Eb7B85807020b4548EE05B54bfC956eEbbfCD"; 

    const wstethAddress = "0x5979D7b546E38E414F7E9822514be443A4800529";
    const wethAddress = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
    const wstethwethPoolAddressPool = "0xdEb89DE4bb6ecf5BFeD581EB049308b52d9b2Da7"; 
    
    async function deployCamelotLiquidity() {
        const camelotLiquidity = await ethers.getContractFactory("CamelotLiquidity");
        camelotLiquidityContract = await camelotLiquidity.deploy(nonfungiblePositionManager);
        await camelotLiquidityContract.waitForDeployment();

        console.log("deploy CamelotLiquidity successfully: %s", await camelotLiquidityContract.getAddress());
    }

    async function getMintPositionResult(tx : ContractTransactionReceipt, index: number) {
        // var camelotLiquidityContractAddressHex = AbiCoder.defaultAbiCoder().encode(["address"], [await camelotLiquidityContract.getAddress()]);
        // var zeroAddressHex = AbiCoder.defaultAbiCoder().encode(["address"], ["0x0000000000000000000000000000000000000000"]);
        var log = tx?.logs.find(l=> l.topics.includes("0x38296fd5286ebdb66bc9ab8003152f9666c9e808b447df47c94f7d2387fb3a54"));
        return AbiCoder.defaultAbiCoder().decode(["uint256", "uint128", "uint256", "uint256"], log!.data)[index];
    }

    async function getIncreasePositionResult(tx : ContractTransactionReceipt, index: number) {
        var log = tx?.logs.find(l=> l.topics.includes("0x0a65cc63f481035bddeace027bb12726628d84152598e98e29635cbcbb0bfa76"));
        return AbiCoder.defaultAbiCoder().decode(["uint256", "uint128", "uint256", "uint256"], log!.data)[index];
    }

    before(async function () {
        nftPosition = await ethers.getContractAt("IERC721", nftPositionAddress);

        usdc = await ethers.getContractAt("IERC20", usdcAddress);
        usdce = await ethers.getContractAt("IERC20", usdceAddress);

        wsteth = await ethers.getContractAt("IERC20", wstethAddress);
        weth = await ethers.getContractAt("IERC20", wethAddress);

        [admin] = await ethers.getSigners();
        await deployCamelotLiquidity();
    });

    // POOL USDC_USDCE TEST
    it.skip("mint position usdc_usdce pool, should create position successfully on camelot dex", async function () {
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
            -887272n,
            887272n,
            usdcAddress,
            usdcAmount,
            usdceAddress,
            usdceAmount
        );
        const transferTx3Result = await transferTx3.wait();  

        liquidityTokenId = await getMintPositionResult(transferTx3Result!, LIQUIDITY_TOKEN_ID);
        liquidityAmount = await getMintPositionResult(transferTx3Result!, LIQUIDITY_AMOUNT);
        console.log("liquidityTokenId: %s liquidityAmount: %s", liquidityTokenId, liquidityAmount);
        const ownerOfNft = await nftPosition.connect(admin).ownerOf(liquidityTokenId);
        console.log("ownerOfNft: %s is: %s", liquidityTokenId, ownerOfNft);
        expect(ownerOfNft).to.equals(await admin.getAddress());

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

    // POOL WSTETH_ETH TEST
    it("mint position weth_wsteth pool, should create position successfully on camelot dex", async function () {
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

        const wethSigner = await ethers.getImpersonatedSigner("0x1eed63efba5f81d95bfe37d82c8e736b974f477b");
        const transferTx1 = await weth.connect(wethSigner).transfer(admin, ethers.parseEther("10"));
        await transferTx1.wait();

        const wstethPoolBalance = await wsteth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        const wstPoolBalance = await weth.connect(admin).balanceOf(wstethwethPoolAddressPool);

        const wstethAmount = ethers.parseUnits("2", 18);
        const wethAmount = ethers.parseUnits("2", 18);

        await wsteth.connect(admin).approve(await camelotLiquidityContract.getAddress(), wstethAmount);
        await weth.connect(admin).approve(await camelotLiquidityContract.getAddress(), wethAmount);

        const transferTx3 = await camelotLiquidityContract.connect(admin).mintPosition(
            -887272n,
            887272n,
            wstethAddress,
            wstethAmount,
            wethAddress,
            wethAmount
        );
        var transferTx3Result = await transferTx3.wait(); 

        liquidityTokenId = await getMintPositionResult(transferTx3Result!, LIQUIDITY_TOKEN_ID);
        liquidityAmount = await getMintPositionResult(transferTx3Result!, LIQUIDITY_AMOUNT);
        console.log("liquidityTokenId: %s liquidityAmount: %s", liquidityTokenId, liquidityAmount);

        const newWstethPoolBalance = await wsteth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        const newWethPoolBalance = await weth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        console.log("balance of pool after mint position: %s wsteth, %s weth", newWstethPoolBalance , newWethPoolBalance);

        expect(newWstethPoolBalance).to.greaterThan(wstethPoolBalance);
        expect(newWethPoolBalance).to.greaterThan(wstPoolBalance);
    });

    it.skip("increase liquidity weth and wsteth pool, should increase successfully on camelot dex", async function () {
        const wstethPoolBalance = await wsteth.connect(admin).balanceOf(wstethwethPoolAddressPool);
        const wstPoolBalance = await weth.connect(admin).balanceOf(wstethwethPoolAddressPool);

        const wstethAmount = ethers.parseUnits("2", 18);
        const wethAmount = ethers.parseUnits("2", 18);

        await wsteth.connect(admin).approve(await camelotLiquidityContract.getAddress(), wstethAmount);
        await weth.connect(admin).approve(await camelotLiquidityContract.getAddress(), wethAmount);

        const transferTx = await camelotLiquidityContract.connect(admin).increaseLiquidityCurrentRange(
            liquidityTokenId,
            wstethAddress,
            wstethAmount,
            wethAddress,
            wethAmount
        );

        var transferTx3Result = await transferTx.wait(); 

        liquidityTokenId = await getIncreasePositionResult(transferTx3Result!, LIQUIDITY_TOKEN_ID);
        liquidityAmount += await getIncreasePositionResult(transferTx3Result!, LIQUIDITY_AMOUNT);
        console.log("liquidityTokenId: %s liquidityAmount: %s", liquidityTokenId, liquidityAmount);

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
    
    it.skip("collect fee weth and wsteth pool, should collect successfully on camelot dex", async function () {
        const transferTx1 = await camelotLiquidityContract.connect(admin).collectAllFees(
            liquidityTokenId
        );
        var transferTx1Result = await transferTx1.wait(); 
        console.log(transferTx1Result?.logs);
    });

    it.skip("decrease liquidity weth and wsteth pool, should decrease successfully on camelot dex", async function () {
        console.log("liquidityTokenId: %s liquidityAmount: %s", liquidityTokenId, liquidityAmount);

        const wstethAdminBalance = await wsteth.connect(admin).balanceOf(admin);
        const ethAdminBalance = await weth.connect(admin).balanceOf(admin);
        console.log("balance of pool before decrease: %s wsteth, %s weth", wstethAdminBalance, ethAdminBalance);

        const transferTx1 = await camelotLiquidityContract.connect(admin).decreaseLiquidityCurrentRange(
            liquidityTokenId,
            liquidityAmount
        );
        await transferTx1.wait(); 
        
        const newWstethAdminBalance = await wsteth.connect(admin).balanceOf(admin);
        const newEthAdminBalance = await weth.connect(admin).balanceOf(admin);
        console.log("balance of pool after decrease: %s wsteth, %s weth", newWstethAdminBalance, newEthAdminBalance);

        const wstethContractBalance = await wsteth.connect(admin).balanceOf(camelotLiquidityContract);
        const wethContractBalance = await weth.connect(admin).balanceOf(camelotLiquidityContract);
        console.log("balance of contract after decrease: %s wsteth, %s weth", wstethContractBalance, wethContractBalance);
    });

    it.skip("collect fee usdc_usdce pool from 0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa, should collect successfully on camelot dex", async function () {
        const usdcPoolBalance = await usdc.connect(admin).balanceOf(admin);
        const usdcePoolBalance = await usdce.connect(admin).balanceOf(admin);
        console.log("balance of pool before collect fee: %s usd, %s usdce", usdcPoolBalance , usdcePoolBalance);

        const tx = await admin.sendTransaction({
            to: "0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa",
            value: ethers.parseEther("0.5")
        });

        const aaSigner = await ethers.getImpersonatedSigner("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");
        await nftPosition.connect(aaSigner).approve(await camelotLiquidityContract.getAddress(), 27617);
        
        const transferTx1 = await camelotLiquidityContract.connect(admin).collectAllFees(
            27617
        );

        var transferTx1Result = await transferTx1.wait(); 
        console.log(transferTx1Result?.logs);

        const newUsdcPoolBalance = await usdc.connect(admin).balanceOf(admin);
        const newUsdcePoolBalance = await usdce.connect(admin).balanceOf(admin);
        console.log("balance of pool after collect fee: %s usd, %s usdce", newUsdcPoolBalance , newUsdcePoolBalance);
    });

    it.skip("decrease liquidity usdc_usdce pool from 0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa, should decrease liquidity successfully on camelot dex", async function () {
        const wstethContractBalance = await wsteth.connect(admin).balanceOf("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");
        const wethContractBalance = await weth.connect(admin).balanceOf("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");

        const tx = await admin.sendTransaction({
            to: "0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa",
            value: ethers.parseEther("0.5")
        });

        const aaSigner = await ethers.getImpersonatedSigner("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");
        await nftPosition.connect(aaSigner).approve(await camelotLiquidityContract.getAddress(), 30679);
        
        const transferTx1 = await camelotLiquidityContract.connect(admin).decreaseLiquidityCurrentRange(
            30679,
            1273496053658204327527n
        );
        await transferTx1.wait(); 

        var transferTx1Result = await transferTx1.wait(); 
        console.log(transferTx1Result?.logs);

        const newWstethContractBalance = await wsteth.connect(admin).balanceOf("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");
        const newWethContractBalance = await weth.connect(admin).balanceOf("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");

        const adminWstethPoolBalance = await wsteth.connect(admin).balanceOf(admin);
        const adminWethPoolBalance = await weth.connect(admin).balanceOf(admin);

        console.log("balance of 0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa before decrease: %s wsteth, %s weth", wstethContractBalance , wethContractBalance);
        console.log("balance of 0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa after decrease: %s wsteth, %s weth", newWstethContractBalance , newWethContractBalance);
        console.log("balance of admin after collect fee: %s wsteth, %s weth", adminWstethPoolBalance , adminWstethPoolBalance);
        
        const transferTx2 = await camelotLiquidityContract.connect(admin).collectAllFees(
            30679
        );

        const new1WstethContractBalance = await wsteth.connect(admin).balanceOf("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");
        const new1WethContractBalance = await weth.connect(admin).balanceOf("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");
        console.log("balance of 0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa after decrease: %s wsteth, %s weth", new1WstethContractBalance , new1WethContractBalance);
    
        const admin1WstethPoolBalance = await wsteth.connect(admin).balanceOf(admin);
        const admint1WethPoolBalance = await weth.connect(admin).balanceOf(admin);
        console.log("balance of admin after decrease: %s wsteth, %s weth", admin1WstethPoolBalance , admint1WethPoolBalance);
    });
});
