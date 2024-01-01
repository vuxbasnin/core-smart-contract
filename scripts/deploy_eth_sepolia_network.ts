import { ethers } from "hardhat";
import * as Contracts from "../typechain-types";
import { Signer } from "ethers";

const nonfungiblePositionManager = "0x00c7f3082833e796A5b3e4Bd59f6642FF44DCD15";
const usdcusdcePoolAddressPool = "0xc86Eb7B85807020b4548EE05B54bfC956eEbbfCD";

// assets
let usdcAddress = "";
let usdceAddress = "";
let wstethAddress = "";
let wethAddress = "";

async function deployMockAsset(tokenName: string, reciver: Signer) {
  // Deploy a mock USDC contract and mint tokens
  const MockERC20Factory = await ethers.getContractFactory("MockERC20");
  const mockUSDC = (await MockERC20Factory.deploy(
    tokenName,
    tokenName
  )) as Contracts.MockERC20;
  const assetAddress = await mockUSDC.getAddress();

  console.log("Deployed %s at address %s", tokenName, assetAddress);
  await mockUSDC.mint(await reciver.getAddress(), ethers.parseEther("10000"));
  return assetAddress;
}

async function deployLiquidityContract() {
  const factory = await ethers.getContractFactory("CamelotLiquidity");
  const camelotLiquidityContract = (await factory.deploy(
    nonfungiblePositionManager,
    usdcusdcePoolAddressPool
  )) as Contracts.CamelotLiquidity;
  const camelotLiquidityAddress = await camelotLiquidityContract.getAddress();

  console.log(
    "Deployed Camelot LP contract at address %s",
    camelotLiquidityAddress
  );

  return camelotLiquidityAddress;
}

async function deployCamelotSwapContract() {
  // Get the Contract Factory
  const MockSwapRouter = await ethers.getContractFactory("MockSwapRouter");

  // Deploy the Contract
  const swapRouter = await MockSwapRouter.deploy();

  const factory = await ethers.getContractFactory("CamelotSwap");
  const camelotSwapContract = (await factory.deploy(
    swapRouter,
    100
  )) as Contracts.CamelotSwap;
  const camelotSwapAddress = await camelotSwapContract.getAddress();
  console.log(
    "Deployed Camelot Swap contract at address %s",
    camelotSwapAddress
  );

  return camelotSwapAddress;
}

async function deployAevoContract() {
  const mockAevoFactory = await ethers.getContractFactory("MockAEVO");
  const aevoMockContract =
    (await mockAevoFactory.deploy()) as Contracts.MockAEVO;

  const factory = await ethers.getContractFactory("AevoOptions");
  const aevoOptionsContract = (await factory.deploy(
    usdceAddress,
    await aevoMockContract.getAddress(),
    await aevoMockContract.getAddress()
  )) as Contracts.AevoOptions;
  const aevoProxyAddress = await aevoOptionsContract.getAddress();
  console.log("Deployed AEVO contract at address %s", aevoProxyAddress);

  return aevoProxyAddress;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // deploy all assets
  usdcAddress = await deployMockAsset("USDC", deployer);
  usdceAddress = await deployMockAsset("USDC.e", deployer);
  wethAddress = await deployMockAsset("WETH", deployer);
  wstethAddress = await deployMockAsset("wstETH", deployer);

  const camelotLiquidityAddress = await deployLiquidityContract();
  const camelotSwapAddress= await deployCamelotSwapContract();
  const aevoProxyAddress =  await deployAevoContract();

  const RockOnyxUSDTVaultFactory = await ethers.getContractFactory("RockOnyxUSDTVault");
  const rockOnyxUSDTVault = await RockOnyxUSDTVaultFactory.deploy(
    usdcAddress,
    camelotLiquidityAddress,
    camelotSwapAddress,
    aevoProxyAddress,
    await deployer.getAddress(),
    usdceAddress,
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // mock data to test options strategy
    usdcAddress,
    wethAddress,
    wstethAddress
  );
  
  console.log("Deployed rockOnyxUSDTVault at address %s", await rockOnyxUSDTVault.getAddress());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
