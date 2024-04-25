const { ethers, network } = require("hardhat");
import { expect } from "chai";

import * as Contracts from "../../typechain-types";
import { Signer, AbiCoder, ContractTransactionReceipt } from "ethers";
import {
    CHAINID,
    WETH_ADDRESS,
    USDC_ADDRESS,
    USDCE_ADDRESS,
    WSTETH_ADDRESS,
    ARB_ADDRESS,
    NonfungiblePositionManager,
    USDC_IMPERSONATED_SIGNER_ADDRESS,
    USDCE_IMPERSONATED_SIGNER_ADDRESS,
    WETH_IMPERSONATED_SIGNER_ADDRESS,
    WSTETH_IMPERSONATED_SIGNER_ADDRESS,
    ANGLE_REWARD_ADDRESS,
  } from "../../constants";

const chainId: CHAINID = network.config.chainId;
// const chainId: CHAINID = 42161;

describe("camelot liquidity contract test", function () {
    let admin: Signer;
    let camelotLiquidityContract: Contracts.CamelotLiquidity;
    let usdc: Contracts.IERC20;
    let usdce: Contracts.IERC20;
    let wsteth: Contracts.IERC20;
    let weth: Contracts.IERC20;
    let arb: Contracts.IERC20;
    let grail: Contracts.IERC20;
    let nftPosition: Contracts.IERC721;
    let liquidityTokenId: number;
    let liquidityAmount: number;

    const LIQUIDITY_TOKEN_ID = 0;
    const LIQUIDITY_AMOUNT = 0;

    const rewardAddress = ANGLE_REWARD_ADDRESS[chainId];
    const usdcImpersonatedSigner = USDC_IMPERSONATED_SIGNER_ADDRESS[chainId];
    const usdceImpersonatedSigner = USDCE_IMPERSONATED_SIGNER_ADDRESS[chainId];
    const wethImpersonatedSigner = WETH_IMPERSONATED_SIGNER_ADDRESS[chainId];
    const wstEthImpersonatedSigner = WSTETH_IMPERSONATED_SIGNER_ADDRESS[chainId];
    const nonfungiblePositionManager = NonfungiblePositionManager[chainId];
    const usdcAddress = USDC_ADDRESS[chainId];
    const usdceAddress = USDCE_ADDRESS[chainId];
    const wstethAddress = WSTETH_ADDRESS[chainId];
    const wethAddress = WETH_ADDRESS[chainId];
    const arbAddress = ARB_ADDRESS[chainId];

    
    async function deployCamelotLiquidity() {
        const camelotLiquidity = await ethers.getContractFactory(
            "CamelotLiquidity"
          );
          camelotLiquidityContract = await camelotLiquidity.deploy(
            nonfungiblePositionManager
          );
          await camelotLiquidityContract.waitForDeployment();
      
          console.log(
            "deploy CamelotLiquidity successfully: %s",
            await camelotLiquidityContract.getAddress()
          );
    }

    async function getMintPositionResult(tx : ContractTransactionReceipt, index: number) {
        var log = tx?.logs.find(l=> l.topics.includes("0x38296fd5286ebdb66bc9ab8003152f9666c9e808b447df47c94f7d2387fb3a54"));
        return AbiCoder.defaultAbiCoder().decode(["uint256", "uint128", "uint256", "uint256"], log!.data)[index];
    }

    async function getIncreasePositionResult(tx : ContractTransactionReceipt, index: number) {
        var log = tx?.logs.find(l=> l.topics.includes("0x0a65cc63f481035bddeace027bb12726628d84152598e98e29635cbcbb0bfa76"));
        return AbiCoder.defaultAbiCoder().decode(["uint256", "uint128", "uint256", "uint256"], log!.data)[index];
    }

    before(async function () {
        nftPosition = await ethers.getContractAt("IERC721", nonfungiblePositionManager);
        usdc = await ethers.getContractAt("IERC20", usdcAddress);
        usdce = await ethers.getContractAt("IERC20", usdceAddress);
        wsteth = await ethers.getContractAt("IERC20", wstethAddress);
        weth = await ethers.getContractAt("IERC20", wethAddress);
        arb = await ethers.getContractAt("IERC20", arbAddress);

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
            to: wstEthImpersonatedSigner,
            value: ethers.parseEther("0.5")
        });
        const tx1 = await admin.sendTransaction({
            to: wethImpersonatedSigner,
            value: ethers.parseEther("0.5")
        });

        const wstethSigner = await ethers.getImpersonatedSigner(wstEthImpersonatedSigner);
        const transferTx0 = await wsteth.connect(wstethSigner).transfer(admin, ethers.parseEther("10"));
        await transferTx0.wait();

        const wethSigner = await ethers.getImpersonatedSigner(wethImpersonatedSigner);
        const transferTx1 = await weth.connect(wethSigner).transfer(admin, ethers.parseEther("10"));
        await transferTx1.wait();

        const wstethAdminBalance = await wsteth.connect(admin).balanceOf(admin);
        const wstAdminBalance = await weth.connect(admin).balanceOf(admin);

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

        const newWstethAdminBalance = await wsteth.connect(admin).balanceOf(admin);
        const newWethAdminBalance = await weth.connect(admin).balanceOf(admin);

        console.log("balance of admin before mint position: %s wsteth, %s weth", wstethAdminBalance , wstAdminBalance);
        console.log("balance of admin after mint position: %s wsteth, %s weth", newWstethAdminBalance , newWethAdminBalance);
    });

    it("increase liquidity weth and wsteth pool, should increase successfully on camelot dex", async function () {
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

        const newWstethAdminBalance = await wsteth.connect(admin).balanceOf(admin);
        const newWethAdminBalance = await weth.connect(admin).balanceOf(admin);
        console.log("balance of admin after increase position: %s wsteth, %s weth", newWstethAdminBalance , newWethAdminBalance);
    });
    
    it("collect fee weth and wsteth pool, sender is not owner's nft, should collect fail on camelot dex", async function () {
        await nftPosition.connect(admin).approve(await camelotLiquidityContract.getAddress(), liquidityTokenId);
        const wstethSigner = await ethers.getImpersonatedSigner(wstEthImpersonatedSigner);

        await expect(camelotLiquidityContract
            .connect(wstethSigner)
            .collectAllFees(liquidityTokenId))
            .to.be.revertedWith("INVALID_TOKENID_OWNER");
    });

    it("collect fee weth and wsteth pool, should collect successfully on camelot dex", async function () {
        await nftPosition.connect(admin).approve(await camelotLiquidityContract.getAddress(), liquidityTokenId);
        const transferTx1 = await camelotLiquidityContract.connect(admin).collectAllFees(
            liquidityTokenId
        );
        var transferTx1Result = await transferTx1.wait(); 
    });

    it("decrease liquidity weth and wsteth pool, should decrease successfully on camelot dex", async function () {
        console.log("liquidityTokenId: %s liquidityAmount: %s", liquidityTokenId, liquidityAmount);

        await nftPosition.connect(admin).approve(await camelotLiquidityContract.getAddress(), liquidityTokenId);
        const transferTx1 = await camelotLiquidityContract.connect(admin).decreaseLiquidityCurrentRange(
            liquidityTokenId,
            liquidityAmount
        );
        await transferTx1.wait(); 

        const transferTx2 = await camelotLiquidityContract.connect(admin).collectAllFees(
            liquidityTokenId
        );
        
        const newWstethAdminBalance = await wsteth.connect(admin).balanceOf(admin);
        const newEthAdminBalance = await weth.connect(admin).balanceOf(admin);
        console.log("balance of admin after decrease: %s wsteth, %s weth", newWstethAdminBalance, newEthAdminBalance);
    });

    it.skip("collect fee usdc_usdce pool from 0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa - 164484718, should collect successfully on camelot dex", async function () {
        const aaSigner = await ethers.getImpersonatedSigner("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");

        const usdcBalance = await usdc.connect(aaSigner).balanceOf(aaSigner);
        const usdceBalance = await usdce.connect(aaSigner).balanceOf(aaSigner);
        console.log("balance of aaSigner before collect fee: %s usdc, %s usdce", usdcBalance , usdceBalance);

        const tx = await admin.sendTransaction({
            to: "0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa",
            value: ethers.parseEther("0.5")
        });

        await nftPosition.connect(aaSigner).approve(await camelotLiquidityContract.getAddress(), 27617);
        const transferTx1 = await camelotLiquidityContract.connect(aaSigner).collectAllFees(
            27617
        );

        await transferTx1.wait(); 

        const newUsdcBalance = await usdc.connect(aaSigner).balanceOf(aaSigner);
        const newUsdceBalance = await usdce.connect(aaSigner).balanceOf(aaSigner);
        console.log("balance of aaSigner after collect fee: %s usdc, %s usdce", newUsdcBalance , newUsdceBalance);

        const admin1arbPoolBalance = await arb.connect(aaSigner).balanceOf(aaSigner);
        const admint1grailPoolBalance = await grail.connect(aaSigner).balanceOf(aaSigner);
        console.log("balance of aaSigner after collect fee: %s arb, %s grail", admin1arbPoolBalance , admint1grailPoolBalance);
    });

    it.skip("unbind liquidity usdc_usdce pool from 0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa - 163785110, should unbind liquidity successfully on camelot dex", async function () {
        const aaSigner = await ethers.getImpersonatedSigner("0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa");

        const wstethAaSingerBalance = await wsteth.connect(admin).balanceOf(aaSigner);
        const wethAaSingerBalance = await weth.connect(admin).balanceOf(aaSigner);

        const tx = await admin.sendTransaction({
            to: "0xbc05da14287317fe12b1a2b5a0e1d756ff1801aa",
            value: ethers.parseEther("0.5")
        });
        
        await nftPosition.connect(aaSigner).approve(await camelotLiquidityContract.getAddress(), 30679);
        
        const transferTx1 = await camelotLiquidityContract.connect(aaSigner).decreaseLiquidityCurrentRange(
            30679,
            1273496053658204327527n
        );
        await transferTx1.wait(); 

        const transferTx2 = await camelotLiquidityContract.connect(aaSigner).collectAllFees(
            30679
        );

        const newWstethAaSingerBalance = await wsteth.connect(aaSigner).balanceOf(aaSigner);
        const newWethAaSingerBalance = await weth.connect(aaSigner).balanceOf(aaSigner);
        console.log("balance of aaSigner before decrease: %s wsteth, %s weth", wstethAaSingerBalance , wethAaSingerBalance);
        console.log("balance of aaSigner after decrease: %s wsteth, %s weth", newWstethAaSingerBalance , newWethAaSingerBalance);
    
        const admin1arbPoolBalance = await arb.connect(aaSigner).balanceOf(aaSigner);
        const admint1grailPoolBalance = await grail.connect(aaSigner).balanceOf(aaSigner);
        console.log("balance of aaSigner after decrease: %s arb, %s grail", admin1arbPoolBalance , admint1grailPoolBalance);
    });
});
