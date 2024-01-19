const { expect } = require("chai");
const { ethers, network } = require("hardhat");
import * as Contracts from "../typechain-types";
import { BigNumberish, ContractTransaction, Signer } from "ethers";
import {
  CHAINID,
  WETH_ADDRESS,
  USDC_ADDRESS,
  USDCE_ADDRESS,
  WSTETH_ADDRESS,
  NonfungiblePositionManager,
  SWAP_ROUTER_ADDRESS,
  AEVO_ADDRESS,
  AEVO_CONNECTOR_ADDRESS,
  USDC_IMPERSONATED_SIGNER_ADDRESS,
  USDCE_IMPERSONATED_SIGNER_ADDRESS,
  WETH_IMPERSONATED_SIGNER_ADDRESS,
  WSTETH_IMPERSONATED_SIGNER_ADDRESS,
} from "../constants";

const chainId: CHAINID = network.config.chainId;

describe("RockOnyxUSDTVault", function () {
  let RockOnyxUSDTVault;
  let rockOnyxUSDTVault: Contracts.RockOnyxUSDTVault;
  const usdcAddress = USDC_ADDRESS[chainId];
  const usdceAddress = USDCE_ADDRESS[chainId];
  console.log("usdceAddress", usdceAddress);
  const wstethAddress = WSTETH_ADDRESS[chainId];
  const wethAddress = WETH_ADDRESS[chainId];
  let usdc: Contracts.IERC20;
  let usdce: Contracts.IERC20;
  let weth: Contracts.IERC20;
  let wsteth: Contracts.IERC20;

  // camelot
  const nonfungiblePositionManager = NonfungiblePositionManager[chainId];
  let camelotLiquidityContract: Contracts.CamelotLiquidity;
  let camelotLiquidityAddress: string;

  // swap router
  const swapRouterAddress = SWAP_ROUTER_ADDRESS[chainId];
  let camelotSwapContract: Contracts.CamelotSwap;
  let camelotSwapAddress: string;

  const aevoAddress = AEVO_ADDRESS[chainId];
  const aevoConnectorAddress = AEVO_CONNECTOR_ADDRESS[chainId];
  let aevoOptionsContract: Contracts.AevoOptions;
  let aevoProxyAddress: string;
  let optionsReceiver: string;

  let owner: Signer,
    user1: Signer,
    user2: Signer,
    user3: Signer,
    user4: Signer,
    user5: Signer;

  async function deployLiquidityContract() {
    const factory = await ethers.getContractFactory("CamelotLiquidity");
    camelotLiquidityContract = (await factory.deploy(
      nonfungiblePositionManager
    )) as Contracts.CamelotLiquidity;
    camelotLiquidityAddress = await camelotLiquidityContract.getAddress();

    console.log(
      "Deployed Camelot LP contract at address %s",
      camelotLiquidityAddress
    );
  }

  async function addLiquidityToSwapProxy(
    asset: Contracts.IERC20,
    amount: number,
    impersonatedAddress: string
  ) {
    const impersonatedSigner = await ethers.getImpersonatedSigner(
      impersonatedAddress
    );

    const transferTx = await asset
      .connect(impersonatedSigner)
      .transfer(camelotSwapAddress, ethers.parseUnits(amount.toString(), 6));
    await transferTx.wait();
    console.log(
      "Transfered fund to SwapProxy %s with amount = %s",
      camelotSwapAddress,
      amount
    );
  }

  async function deployCamelotSwapContract() {
    if (chainId == CHAINID.ARBITRUM_MAINNET) {
      console.log("swapRouterAddress = %s", swapRouterAddress);
      const swapRouter = await ethers.getContractAt(
        "ISwapRouter",
        swapRouterAddress
      );

      const factory = await ethers.getContractFactory("CamelotSwap");
      camelotSwapContract = (await factory.deploy(
        swapRouter
      )) as Contracts.CamelotSwap;
      camelotSwapAddress = await camelotSwapContract.getAddress();
      console.log(
        "Deployed Camelot Swap contract at address %s",
        camelotSwapAddress
      );
    } else if (chainId == CHAINID.ETH_SEPOLIA) {
      // On Ethereum testnet, we don't have swapPool then we use the MockSwap instead of
      const factory = await ethers.getContractFactory("RockOnyxSwap");
      camelotSwapContract = (await factory.deploy(
        "0xE592427A0AEce92De3Edee1F18E0157C05861564" // we don't use this then just a mock value
      )) as Contracts.CamelotSwap;
      camelotSwapAddress = await camelotSwapContract.getAddress();

      console.log(
        "Deployed RockOnyxSwap contract at address %s",
        camelotSwapAddress
      );

      await addLiquidityToSwapProxy(
        usdc,
        50000,
        USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? ""
      );

      await addLiquidityToSwapProxy(
        usdce,
        50000,
        USDCE_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? ""
      );

      await addLiquidityToSwapProxy(
        weth,
        500,
        WETH_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? ""
      );

      await addLiquidityToSwapProxy(
        wsteth,
        500,
        WSTETH_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? ""
      );
    }
  }

  async function deployAevoContract() {
    const factory = await ethers.getContractFactory("AevoOptions");
    aevoOptionsContract = (await factory.deploy(
      usdceAddress,
      aevoAddress,
      aevoConnectorAddress
    )) as Contracts.AevoOptions;
    aevoProxyAddress = await aevoOptionsContract.getAddress();
    console.log("Deployed AEVO contract at address %s", aevoProxyAddress);
  }

  // Helper function for deposit
  async function deposit(sender: Signer, amount: BigNumberish) {
    const userAddress = await sender.getAddress();
    console.log(
      `Depositing ${ethers.formatUnits(amount, 6)} USDC for ${userAddress}`
    );
    await usdc
      .connect(sender)
      .approve(await rockOnyxUSDTVault.getAddress(), amount);
    console.log("approved");
    await rockOnyxUSDTVault.connect(sender).deposit(amount);
  }

  // Helper function for withdrawal
  async function withdraw(user: Signer, shares: BigNumberish) {
    const userAddress = await user.getAddress();
    console.log(
      `Withdrawing ${ethers.formatUnits(shares, 6)} USDC for ${userAddress}`
    );
    await rockOnyxUSDTVault.connect(user).initiateWithdrawal(shares);
  }

  async function transferIERC20FundForUser(
    asset: Contracts.IERC20,
    from: string,
    to: Signer,
    amount: number
  ) {
    const impersonatedSigner = await ethers.getImpersonatedSigner(from);
    const recipientAddress = await to.getAddress();

    console.log(
      "balance of impersonatedSigner",
      await asset
        .connect(impersonatedSigner)
        .balanceOf(await impersonatedSigner.getAddress())
    );

    const transferTx = await asset
      .connect(impersonatedSigner)
      .transfer(recipientAddress, ethers.parseUnits(amount.toString(), 6));
    await transferTx.wait();

    const balanceOfUser = await asset.connect(to).balanceOf(optionsReceiver);
    console.log("Balance of user %s", balanceOfUser);
  }

  async function logBalances() {
    const pricePerShare = await rockOnyxUSDTVault.pricePerShare();
    const totalSupply = await rockOnyxUSDTVault.totalValueLocked();
    console.log(
      "Price/Share %s, totalAssets= %s",
      ethers.formatUnits(pricePerShare.toString(), 6),
      ethers.formatUnits(totalSupply, 6)
    );
  }

  beforeEach(async function () {
    console.log("usdcAddress %s", usdcAddress, chainId);
    usdc = await ethers.getContractAt("IERC20", usdcAddress);
    usdce = await ethers.getContractAt("IERC20", usdceAddress);

    RockOnyxUSDTVault = await ethers.getContractFactory("RockOnyxUSDTVault");
    [owner, user1, user2, user3, user4, user5] = await ethers.getSigners();

    await deployLiquidityContract();
    await deployCamelotSwapContract();
    await deployAevoContract();

    rockOnyxUSDTVault = await RockOnyxUSDTVault.deploy(
      usdcAddress,
      camelotLiquidityAddress,
      nonfungiblePositionManager,
      camelotSwapAddress,
      aevoProxyAddress,
      await user1.getAddress(),
      usdceAddress,
      wethAddress,
      wstethAddress
    );

    // transfer fund for user
    optionsReceiver = await user1.getAddress();

    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user1,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user2,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user3,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user4,
      5000
    );
    await transferIERC20FundForUser(
      usdc,
      USDC_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user5,
      5000
    );
    await transferIERC20FundForUser(
      usdce,
      USDCE_IMPERSONATED_SIGNER_ADDRESS[chainId] ?? "",
      user1,
      5000
    );
  });

  it("should handle acquireWithdrawalFundsUsdOptions correctly", async function () {
    console.log("Testing withdraw functionality...");

    // User1 deposits 1000
    await deposit(user3, ethers.parseUnits("1000", 6));

    // check price per share
    await logBalances();

    const balanceOfUser = await usdce.connect(user1).balanceOf(user1);
    console.log(
      "Balance of user %s",
      ethers.formatUnits(balanceOfUser.toString(), 6)
    );

    const depositAmount = ethers.parseUnits("150", 6);

    console.log(`Depositing ${depositAmount} USDC options`);
    await rockOnyxUSDTVault.connect(owner).depositToVendor(depositAmount, {
      value: ethers.parseEther("0.001753"),
    });

    // trader update money back to the vault
    const withdrawAmount = ethers.parseUnits("150", 6);

    await usdce
      .connect(user1)
      .approve(await rockOnyxUSDTVault.getAddress(), withdrawAmount);

    console.log("Trader approved money to handlePostWithdrawalFromVendor");

    await rockOnyxUSDTVault
      .connect(user1)
      .handlePostWithdrawalFromVendor(withdrawAmount);

    // after trader send fund back to vault, owner request acquireWithdrawalFundsUsdOptions
    // in happy case, we assume that withdrawAmount that trader send back to vault always > acquireWithdrawalAmount
    await rockOnyxUSDTVault
      .connect(owner)
      .acquireWithdrawalFundsUsdOptions(ethers.parseUnits("120", 6));
  });

  it.skip("should enforce role-based access control", async function () {
    // Use a non-admin signer
    const nonAdmin = user2;
    const nonAdminAddress = await user2.getAddress();
    const depositAmount = ethers.parseUnits("100", 6);

    // Attempt to call a sensitive function
    await expect(
      rockOnyxUSDTVault.connect(nonAdmin).depositToVendor(depositAmount, {
        value: ethers.parseEther("0.001753"),
      })
    ).to.be.revertedWith("ROCK_ONYX_ADMIN_ROLE_ERROR");
  });
});
