import { ethers } from "hardhat";
import * as Contracts from "../typechain-types";
import { Signer } from "ethers";

const nonfungiblePositionManager = "0x00c7f3082833e796A5b3e4Bd59f6642FF44DCD15";

// assets
let usdcAddress = "";
let usdceAddress = "";
let wstethAddress = "";
let wethAddress = "";
let usdc: Contracts.IERC20;
let usdce: Contracts.IERC20;
let weth: Contracts.IERC20;
let wsteth: Contracts.IERC20;
let deployer: Signer;

async function deployMockAsset(
  tokenName: string,
  reciver: Signer,
  decimals: number
) {
  let MockERC20Factory;
  // Deploy a mock USDC contract and mint tokens
  if (tokenName.startsWith("USD"))
    MockERC20Factory = await ethers.getContractFactory("MockStableCoin");
  else MockERC20Factory = await ethers.getContractFactory("MockETH");

  const mockUSDC = (await MockERC20Factory.deploy(
    tokenName,
    tokenName
  )) as Contracts.MockStableCoin;
  const assetAddress = await mockUSDC.getAddress();

  console.log("Deployed %s at address %s", tokenName, assetAddress);
  return assetAddress;
}

async function deployLiquidityContract() {
  const factory = await ethers.getContractFactory("CamelotLiquidity");
  const camelotLiquidityContract = (await factory.deploy(
    nonfungiblePositionManager
  )) as Contracts.CamelotLiquidity;
  const camelotLiquidityAddress = await camelotLiquidityContract.getAddress();

  console.log(
    "Deployed Camelot LP contract at address %s",
    camelotLiquidityAddress
  );

  return camelotLiquidityAddress;
}

async function addLiquidityToPool(swapRouterAddress: string) {
  const transferTx = await usdce
    .connect(deployer)
    .transfer(swapRouterAddress, ethers.parseUnits("100000", 6));
  await transferTx.wait();

  const transferTx2 = await usdc
    .connect(deployer)
    .transfer(swapRouterAddress, ethers.parseUnits("100000", 6));
  await transferTx2.wait();

  const transferTx3 = await weth
    .connect(deployer)
    .transfer(swapRouterAddress, ethers.parseUnits("100000", 6));
  await transferTx3.wait();

  const transferTx4 = await wsteth
    .connect(deployer)
    .transfer(swapRouterAddress, ethers.parseUnits("100000", 6));
  await transferTx4.wait();
}

async function deployCamelotSwapContract() {
  // Get the Contract Factory
  const MockSwapRouter = await ethers.getContractFactory("MockSwapRouter");

  // Deploy the Contract
  const swapRouter = await MockSwapRouter.deploy();
  console.log("Deployed SwapRouter %s", await swapRouter.getAddress());


  const factory = await ethers.getContractFactory("RockOnyxSwap");
  const camelotSwapContract = await factory.deploy(
    await swapRouter.getAddress()
  );
  await camelotSwapContract.waitForDeployment();

  // await addLiquidityToPool(await camelotSwapContract.getAddress());
  
  console.log(
    "Deployed Camelot Swap contract at address %s",
    await camelotSwapContract.getAddress()
  );

  return await camelotSwapContract.getAddress();
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
  [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", await deployer.getAddress());

  // deploy all assets
  usdcAddress = await deployMockAsset("USDC", deployer, 6);
  usdceAddress = await deployMockAsset("USDC.e", deployer, 6);
  wethAddress = await deployMockAsset("WETH", deployer, 18);
  wstethAddress = await deployMockAsset("wstETH", deployer, 18);
  // usdcAddress = "0xA33a482E2e470E2d1286d0e791923657F59428f2";
  // usdceAddress = "0xd654B1bA9FfC696285FA8deF26eEbAdD7D875033";
  // wethAddress = "0x5551d35dE07BebC4e6a5FAdc1c9073ce02a02b5F";
  // wstethAddress = "0x2C5E28dEaa0E10241Ba38d136EBed75037732c15";

  usdc = await ethers.getContractAt("IERC20", usdcAddress);
  usdce = await ethers.getContractAt("IERC20", usdceAddress);
  weth = await ethers.getContractAt("IERC20", wethAddress);
  wsteth = await ethers.getContractAt("IERC20", wstethAddress);

  const camelotLiquidityAddress = await deployLiquidityContract();
  const camelotSwapAddress = await deployCamelotSwapContract();
  const aevoProxyAddress = await deployAevoContract();

  const RockOnyxUSDTVaultFactory = await ethers.getContractFactory(
    "RockOnyxUSDTVault"
  );

  const rockOnyxUSDTVault = await RockOnyxUSDTVaultFactory.deploy(
    usdcAddress,
    camelotLiquidityAddress,
    "",
    nonfungiblePositionManager,
    camelotSwapAddress,
    aevoProxyAddress,
    await deployer.getAddress(),
    usdceAddress,
    wethAddress,
    wstethAddress,
    ""
  );

  // const rockOnyxUSDTVault = await RockOnyxUSDTVaultFactory.deploy(
  //   "0x7EcC4336139478846119367d925Ff2Ae84FB7570",
  //   "0xdcEC81AB071CE37686E0d37306081c3a935F3a3d",
  //   nonfungiblePositionManager,
  //   "0xF7AEE7e9bc25143C9EAAF1a768dA052F0AaB94b7",
  //   "0x81b1BF4864C57EFd5ABC3972A958C7318652E49f",
  //   await deployer.getAddress(),
  //   "0x411bbe0c596df21bd7Cd89dc86B22e4a08F9974F",
  //   "0x58DBa498a48Fe97074fa01c8de86F6D6aed534c9",
  //   "0xe4D5818BE503A858C070356bACa2e4839Cf541df"
  // );

  console.log(
    "Deployed rockOnyxUSDTVault at address %s",
    await rockOnyxUSDTVault.getAddress()
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
