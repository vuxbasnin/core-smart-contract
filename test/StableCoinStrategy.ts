import { ethers, network } from "hardhat";
import { expect } from "chai";
import { BigNumberish, ContractTransaction, Signer } from "ethers";
import * as Contracts from "../typechain-types"; // Adjust the path as necessary

interface MockERC20 extends Contracts.IERC20 {
  mint: (account: string, amount: BigNumberish) => Promise<ContractTransaction>;
}

describe("OnyxVault on Mainnet Fork", function () {
  let owner: Signer,
    user1: Signer,
    user2: Signer,
    user3: Signer,
    user4: Signer,
    user5: Signer;
  let onyxVault: Contracts.StableCoinStrategy;
  let usdcAddress;
  let mockUSDC: MockERC20;

  // Helper function for deposit
  async function deposit(user: Signer, amount: BigNumberish) {
    const userAddress = await user.getAddress();
    console.log(
      `Depositing ${ethers.formatEther(amount)} USDC for ${userAddress}`
    );
    await mockUSDC.connect(user).approve(await onyxVault.getAddress(), amount);
    await onyxVault.connect(user).deposit(amount);
  }

  // Helper function for withdrawal
  async function withdraw(user: Signer, amount: BigNumberish) {
    const userAddress = await user.getAddress();
    console.log(
      `Withdrawing ${ethers.formatEther(amount)} USDC for ${userAddress}`
    );
    await onyxVault.connect(user).withdraw(amount);
  }

  // Helper function to log balances
  async function logBalances() {
    const pricePerShare = await onyxVault.pricePerShare();
    const totalSupply = await onyxVault.totalSupply();
    const totalBalance = await onyxVault.totalBalance();
    console.log(
      "Price/Share %s, totalSupply= %s, totalBalance=%s",
      ethers.formatEther(pricePerShare.toString()),
      ethers.formatEther(totalSupply),
      ethers.formatEther(totalBalance)
    );
  }

  beforeEach(async function () {
    [owner, user1, user2, user3, user4, user5] = await ethers.getSigners();

    // Deploy a mock USDC contract and mint tokens
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    mockUSDC = (await MockUSDC.deploy()) as MockERC20;
    usdcAddress = await mockUSDC.getAddress();
    console.log("Deployed mUSDC at address %s", usdcAddress);

    // Mint USDC tokens to user1
    await mockUSDC.mint(await user1.getAddress(), ethers.parseEther("10000"));
    await mockUSDC.mint(await user2.getAddress(), ethers.parseEther("10000"));
    await mockUSDC.mint(await user3.getAddress(), ethers.parseEther("10000"));
    await mockUSDC.mint(await user4.getAddress(), ethers.parseEther("10000"));
    await mockUSDC.mint(await user5.getAddress(), ethers.parseEther("10000"));

    // Deploy your OnyxVault contract (adjust with correct types and constructor arguments)
    onyxVault = await ethers.deployContract("StableCoinStrategy", [
      usdcAddress,
      ethers.parseEther("4000000"),
    ]);
    onyxVault.initialize(await owner.getAddress());
    console.log(
      "Deployed Onyx Vault to address %s, owner: %s",
      await onyxVault.getAddress(),
      await owner.getAddress()
    );
  });

  it.skip("should allow deposit of USDC", async function () {
    // Simulate USDC transfer to user1 for testing

    // console.log("1000 ETH = %s", ethers.parseEther("1000"));
    // await network.provider.send("hardhat_setBalance", [
    //   await user1.getAddress(),
    //   "0x3635c9adc5dea00000",
    // ]);

    // User1 approves OnyxVault to spend their USDC
    const depositAmount = ethers.parseEther("500.1"); // 500 USDC
    console.log(
      "User1 approving OnyxVault to spend %d USDC...",
      ethers.formatEther(depositAmount)
    );
    const usdc = await mockUSDC.connect(user1);
    await usdc.approve(await onyxVault.getAddress(), depositAmount);

    console.log("User1 depositing USDC into the OnyxVault...");
    // User1 deposits USDC into the OnyxVault
    await onyxVault.connect(user1).deposit(depositAmount);

    console.log("Checking user balance after deposit...");
    // Assertions
    const userBalance = await onyxVault.balanceOf(await user1.getAddress());
    console.log("User balance is:", ethers.formatEther(userBalance));
    expect(userBalance).to.equal(depositAmount);
  });

  it.skip("should handle deposits correctly", async function () {
    console.log("Testing deposit functionality...");

    // User1 deposits 1000
    await deposit(user1, ethers.parseEther("1000"));

    // check price per share
    await logBalances();

    // User2 deposits 500
    await deposit(user2, ethers.parseEther("500"));

    // check price per share
    await logBalances();

    // Assertions
    const user1Address = user1.getAddress();
    const user2Address = user2.getAddress();
    const totalSupplyAfter = await onyxVault.totalSupply();
    const totalBalanceAfter = await onyxVault.totalBalance();
    const user1BalanceAfter = await onyxVault.balanceOf(user1Address);
    const user2BalanceAfter = await onyxVault.balanceOf(user2Address);

    expect(totalSupplyAfter).to.equal(ethers.parseEther("1500"));
    expect(totalBalanceAfter).to.equal(ethers.parseEther("1500"));
    expect(user1BalanceAfter).to.equal(ethers.parseEther("1000"));
    expect(user2BalanceAfter).to.equal(ethers.parseEther("500"));
  });

  it.skip("handles deposits and withdrawals correctly for Testcase 1", async function () {
    // Testcase 1: Sequential Deposits and Withdrawals with Profit

    // User1 deposits 1000
    await deposit(user1, ethers.parseEther("1000"));
    // User2 deposits 1500
    await deposit(user2, ethers.parseEther("1500"));
    // User3 deposits 2000
    await deposit(user3, ethers.parseEther("2000"));

    await logBalances();

    // User1 withdraws 500
    await withdraw(user1, ethers.parseEther("500"));
    // User2 withdraws 1000
    await withdraw(user2, ethers.parseEther("1000"));

    await logBalances();

    // Close round with profit
    console.log("Close round...");
    await onyxVault.connect(owner).closeRound(ethers.parseUnits("300", 18));

    // Log balances and perform assertions
    await logBalances();
    // Add expect assertions as needed
  });

  it("Testcase 2: Simultaneous Deposits and Withdrawal with Loss", async function () {

    // User1 deposits 1000
    await deposit(user1, ethers.parseEther("2000"));
    // User2 deposits 1500
    await deposit(user2, ethers.parseEther("1000"));
    // User3 deposits 2000
    await deposit(user3, ethers.parseEther("1500"));

    // User1 withdraws 1000
    await withdraw(user1, ethers.parseEther("1000"));

    await logBalances();

    // Close round with profit
    console.log("Vault closes options, incurring a loss of 200.");
    await onyxVault.connect(owner).closeRound(-ethers.parseEther("200"));

    // User4 deposits on Day 5
    await deposit(user4, ethers.parseEther("1000"));
    await deposit(user5, ethers.parseEther("500"));

    await logBalances();

    // Assertions
    const totalBalance = await onyxVault.totalBalance();
    const totalSupply = await onyxVault.totalSupply();

    // Asserting the final total balance and total supply
    // The expected total balance would be the sum of all deposits minus the withdrawal and the loss
    const expectedTotalBalance =
      ethers.parseEther("5000") - ethers.parseEther("200"); // 5000 - 200
    expect(totalBalance).to.equal(expectedTotalBalance);
  });
});
