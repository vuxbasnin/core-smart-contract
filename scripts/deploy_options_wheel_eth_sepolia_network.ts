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
  const factory = await ethers.getContractFactory("Aevo");
  const aevoOptionsContract = (await factory.deploy(
    usdcAddress,
    await aevoMockContract.getAddress(),
    await aevoMockContract.getAddress()
  )) as Contracts.Aevo;
  const aevoProxyAddress = await aevoOptionsContract.getAddress();
  console.log("Deployed AEVO contract at address %s", aevoProxyAddress);

  return aevoProxyAddress;
}

async function main() {
  [deployer] = await ethers.getSigners();
  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );

  // deploy all assets
  // usdcAddress = await deployMockAsset("roUSDC", deployer, 6);
  // usdceAddress = await deployMockAsset("roUSDC.e", deployer, 6);
  // wethAddress = await deployMockAsset("roWETH", deployer, 18);
  // wstethAddress = await deployMockAsset("roWstETH", deployer, 18);
  // const arbAddress = await deployMockAsset("roARB", deployer, 18);
  usdcAddress = "0xba2C2BeDE721F22A87811E744dfA8ad1BBa1e496";
  usdceAddress = "0x8b46A495C9fcabD15376527F7D0131DC666c7164";
  wethAddress = "0x221744E913cDC73Bc64E8064899F55afc16C535c";
  wstethAddress = "0x5816AEd6DC51334671b41f290Fa3B9ce364B13aD";
  const arbAddress = "0x9E66B862fDDD2D80DA47Ff585E5e121D4b88f9d1";

  usdc = await ethers.getContractAt("IERC20", usdcAddress);
  usdce = await ethers.getContractAt("IERC20", usdceAddress);
  weth = await ethers.getContractAt("IERC20", wethAddress);
  wsteth = await ethers.getContractAt("IERC20", wstethAddress);

  // const camelotLiquidityAddress = await deployLiquidityContract();
  // const camelotSwapAddress = await deployCamelotSwapContract();
  // const aevoProxyAddress = await deployAevoContract();

  const camelotLiquidityAddress = "0x77AbF3d7fD0Fc929c53469D8Cf009274fff21326";
  const camelotSwapAddress = "0x15003f1aD9389C7FF249cA93C88EC5072aBb1963";
  const aevoProxyAddress = "0xD7eaE0B3a08F267e8ed6b0d7BD07c23D88d1Af14";

  const aevoTrader = "0x33F4EF3d84cb354e2E825FBDA4B4DBF579B2dBF0";

  const RockOnyxUSDTVaultFactory = await ethers.getContractFactory(
    "RockOnyxUSDTVault"
  );

  const rockOnyxUSDTVault = await RockOnyxUSDTVaultFactory.deploy(
    usdcAddress,
    camelotLiquidityAddress,
    "0x0000000000000000000000000000000000000000",
    nonfungiblePositionManager,
    camelotSwapAddress,
    aevoProxyAddress,
    aevoTrader,
    usdceAddress,
    wethAddress,
    wstethAddress,
    arbAddress,
    BigInt(0)
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
