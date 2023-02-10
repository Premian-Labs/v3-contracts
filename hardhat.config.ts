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
  API_KEY_ETHERSCAN,
  API_KEY_OPTIMISM,
  API_KEY_ARBISCAN,
  API_KEY_FTMSCAN,
  PKEY_ETH_MAIN,
  PKEY_ETH_TEST,
  FORK_MODE,
  FORK_BLOCK_NUMBER,
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
    },
  },
  paths: {
    cache: CACHE_PATH ?? './cache',
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      blockGasLimit: 180000000000,
      ...(FORK_MODE === 'true'
        ? {
            forking: {
              url: `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
              blockNumber: parseInt(FORK_BLOCK_NUMBER ?? '13717777'),
            },
          }
        : {}),
    },
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [PKEY_ETH_MAIN],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      // gasPrice: 100000000000,
      timeout: 100000,
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [PKEY_ETH_TEST],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    kovan: {
      url: `https://eth-kovan.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [PKEY_ETH_TEST],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    ropsten: {
      url: `https://eth-ropsten.alchemyapi.io/v2/${API_KEY_ALCHEMY}`,
      accounts: [PKEY_ETH_TEST],
      //gas: 120000000000,
      blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    optimism: {
      url: `https://mainnet.optimism.io`,
      accounts: [PKEY_ETH_MAIN],
      timeout: 300000,
    },
    arbitrum: {
      url: `https://arb1.arbitrum.io/rpc`,
      accounts: [PKEY_ETH_MAIN],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      //gasPrice: 10,
      timeout: 300000,
    },
    rinkebyArbitrum: {
      url: `https://rinkeby.arbitrum.io/rpc`,
      accounts: [PKEY_ETH_TEST],
      //gas: 120000000000,
      // blockGasLimit: 120000000000,
      // gasPrice: 100000000000,
      timeout: 100000,
    },
    fantomDev: {
      url: `https://rpc.ftm.tools/`,
      accounts: [PKEY_ETH_TEST],
      timeout: 100000,
    },
    fantom: {
      url: `https://rpc.ftm.tools/`,
      accounts: [PKEY_ETH_MAIN],
      timeout: 100000,
    },
  },

  abiExporter: {
    runOnCompile: false,
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
      mainnet: API_KEY_ETHERSCAN,
      arbitrumOne: API_KEY_ARBISCAN,
      opera: API_KEY_FTMSCAN,
      optimisticEthereum: API_KEY_OPTIMISM,
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
