// Note: Should update priceConsumerAddress and redeploy camelotSwapContract before deploy the vault in next release
import { ethers, network } from "hardhat";
import * as Contracts from "../typechain-types";
import { Signer } from "ethers";
import {
  CHAINID,
  USDC_ADDRESS,
  NonfungiblePositionManager,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDCE_ADDRESS,
  USDT_ADDRESS,
  DAI_ADDRESS,
  WSTETH_ADDRESS,
  WETH_ADDRESS,
  ARB_ADDRESS,
  ANGLE_REWARD_ADDRESS,
  CAMELOT_SWAP_ADDRESS,
  CAMELOT_LIQUIDITY_ADDRESS,
  UNI_SWAP_ADDRESS,
  NETWORK_COST
} from "../constants";

const chainId: CHAINID = network.config.chainId ?? 0;
let deployer: Signer;

// assets
const usdcAddress = USDC_ADDRESS[chainId] ?? "";
const usdceAddress = USDCE_ADDRESS[chainId] ?? "";
const usdtAddress = USDT_ADDRESS[chainId] || "";
const daiAddress = DAI_ADDRESS[chainId] || "";
const wstethAddress = WSTETH_ADDRESS[chainId] ?? "";
const wethAddress = WETH_ADDRESS[chainId] ?? "";
const arbAddress = ARB_ADDRESS[chainId] ?? "";
const nonfungiblePositionManager = NonfungiblePositionManager[chainId] ?? "";
const rewardAddress = ANGLE_REWARD_ADDRESS[chainId] ?? "";
const aevoAddress = AEVO_ADDRESS[chainId] ?? "";
const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId] ?? "";
const uniSwapAddress = UNI_SWAP_ADDRESS[chainId] || "";
const camelotSwapAddress = CAMELOT_SWAP_ADDRESS[chainId] || "";
const camelotLiquidityAddress = CAMELOT_LIQUIDITY_ADDRESS[chainId] || "";
const networkCost = BigInt(Number(NETWORK_COST[chainId]) * 1e6);
const admin = '0x0cD2568E24Ed7Ed47E42075545D49C21e895B54c';
const aevoRecipientAddress = "0xdf46e88E2e26FC90B8e3ca4D36fA524406b0Cc19";

async function main() {
  [deployer] = await ethers.getSigners();
  console.log(
    "Deploying contracts with the account:",
    await deployer.getAddress()
  );

  const RockOnyxUSDTVaultFactory = await ethers.getContractFactory(
    "RockOnyxUSDTVault"
  );
  const rockOnyxUSDTVault = await RockOnyxUSDTVaultFactory.deploy(
    admin,
    usdcAddress,
    6,
    BigInt(5 * 1e6),
    BigInt(1000000 * 1e6),
    networkCost,
    camelotLiquidityAddress,
    rewardAddress,
    nonfungiblePositionManager,
    camelotSwapAddress,
    aevoAddress,
    aevoRecipientAddress,
    aevoConnectorAddress,
    usdceAddress,
    wethAddress,
    wstethAddress,
    arbAddress,
    BigInt(1.213 * 1e6),
    uniSwapAddress,
    [usdtAddress, daiAddress],
    [usdcAddress, usdtAddress],
    [100, 100]
  );

  console.log(
    "Deployed option wheel at address %s",
    await rockOnyxUSDTVault.getAddress()
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});