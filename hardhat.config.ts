import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const { PRIVATE_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
      viaIR: true,
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://arbitrum-mainnet.infura.io/v3/85cde589ce754dafa0a57001c326104d",
        blockNumber: 162977851
      },
    },
    arbitrum: {
      url: "https://arbitrum-mainnet.infura.io/v3/85cde589ce754dafa0a57001c326104d",
      accounts: ['0xea7aab9140a5b271551c74b1a12933c793eeef19cdbf466409a9e46e30b4d7ba']
    },
    localhost: {
      url: "http://127.0.0.1:8545"
    },
  },
};

export default config;
