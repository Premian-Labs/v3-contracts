import Dotenv from 'dotenv';
// Hardhat plugins
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@solidstate/hardhat-4byte-uploader';
import '@solidstate/hardhat-test-short-circuit';
import '@typechain/hardhat';
import 'hardhat-abi-exporter';
import 'hardhat-artifactor';
import 'hardhat-contract-sizer';
import 'hardhat-dependency-compiler';
import 'hardhat-docgen';
import 'hardhat-gas-reporter';
import 'hardhat-spdx-license-identifier';
import 'solidity-coverage';

Dotenv.config();

const {
  API_KEY_ALCHEMY,
  API_KEY_ARBISCAN,
  PKEY_ETH_MAIN,
  PKEY_ETH_TEST,
  REPORT_GAS,
  CACHE_PATH,
} = process.env;

const UNISWAP_SETTING = {
  version: '0.7.6',
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
    },
  },
};

// As the PKEYs are only used for deployment, we use default dummy PKEYs if none are set in .env file, so that project can compile
const pkeyMainnet =
  PKEY_ETH_MAIN == undefined || PKEY_ETH_MAIN.length == 0
    ? 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    : PKEY_ETH_MAIN;
const pkeyTestnet =
  PKEY_ETH_TEST == undefined || PKEY_ETH_TEST.length == 0
    ? 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    : PKEY_ETH_TEST;

export default {
  solidity: {
    compilers: [
      {
        version: '0.8.18',
        settings: {
          viaIR: false,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      UNISWAP_SETTING,
    ],
    overrides: {
      '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol':
        UNISWAP_SETTING,
      '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol':
        UNISWAP_SETTING,
      '@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol':
        UNISWAP_SETTING,
      'contracts/staking/VxPremia.sol': {
        version: '0.8.17',
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  paths: {
    cache: CACHE_PATH ?? './cache',
  },
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
        blockNumber: 16600000,
      },
      allowUnlimitedContractSize: true,
      blockGasLimit: 180000000000,
    },
    arbitrum: {
      url: `https://arb-mainnet.g.alchemy.com/v2/${API_KEY_ALCHEMY}`,
      accounts: [pkeyMainnet],
      timeout: 300000,
    },
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [pkeyTestnet],
      timeout: 300000,
    },
    arbitrumNova: {
      url: `https://nova.arbitrum.io/rpc`,
      accounts: [pkeyMainnet],
      timeout: 300000,
    },
  },

  abiExporter: {
    runOnCompile: true,
    path: './abi',
    clear: true,
    flat: true,
    except: ['@uniswap'],
  },

  docgen: {
    runOnCompile: false,
    clear: true,
  },

  etherscan: {
    apiKey: {
      arbitrumOne: API_KEY_ARBISCAN,
    },
  },

  gasReporter: {
    enabled: REPORT_GAS === 'true',
  },

  spdxLicenseIdentifier: {
    overwrite: false,
    runOnCompile: true,
  },

  typechain: {
    alwaysGenerateOverloads: true,
    outDir: 'typechain',
  },

  mocha: {
    timeout: 6000000,
  },
};
