import {
  ContractDeploymentMetadata,
  ContractKey,
} from './utils/deployment/types';
import {
  initialize,
  verifyContractsOnEtherscan,
} from './utils/deployment/deployment';
import { ethers } from 'hardhat';

const proxyUpgradableOwnablePath =
  'contracts/proxy/ProxyUpgradeableOwnable.sol:ProxyUpgradeableOwnable';
const optionPsProxyPath =
  'contracts/mining/optionPS/OptionPSProxy.sol:OptionPSProxy';
const optionRewardProxyPath =
  'contracts/mining/optionReward/OptionRewardProxy.sol:OptionRewardProxy';
const underwriterVaultProxyPath =
  'contracts/vault/strategies/underwriter/UnderwriterVaultProxy.sol:UnderwriterVaultProxy';
const dualMiningProxyPath =
  'contracts/mining/dualMining/DualMiningProxy.sol:DualMiningProxy';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  for (const category in deployment) {
    if (
      category !== 'core' &&
      category !== 'optionPS' &&
      category !== 'optionReward' &&
      category !== 'vaults' &&
      category !== 'dualMining'
    )
      continue;

    for (let contract in deployment[category]) {
      console.log(`Verifying ${contract}`);

      contract = contract as ContractKey | string;
      let address: string;
      let deploymentArgs: any[];
      let deploymentMetadata: ContractDeploymentMetadata;

      if (category === 'core') {
        deploymentMetadata = deployment[category][contract as ContractKey];
      } else {
        deploymentMetadata = deployment[category][contract as string];
      }

      address = deploymentMetadata.address;
      deploymentArgs = deploymentMetadata.deploymentArgs;

      if (!address) continue;

      let libraries = {};
      let contractPath: string | undefined;

      if (contract === ContractKey.UnderwriterVaultImplementation) {
        libraries = {
          OptionMathExternal: deployment.core.OptionMathExternal.address,
        };
      } else if (
        contract === ContractKey.ChainlinkAdapterProxy ||
        contract === ContractKey.UserSettingsProxy ||
        contract === ContractKey.VaultRegistryProxy ||
        contract === ContractKey.VolatilityOracleProxy ||
        contract === ContractKey.OptionPSFactoryProxy ||
        contract === ContractKey.OptionRewardFactoryProxy ||
        contract === ContractKey.PaymentSplitterProxy
      ) {
        contractPath = proxyUpgradableOwnablePath;
      } else if (contract === ContractKey.PoolFactoryProxy) {
        contractPath =
          'contracts/factory/PoolFactoryProxy.sol:PoolFactoryProxy';
      } else if (contract === ContractKey.ReferralProxy) {
        contractPath = 'contracts/referral/ReferralProxy.sol:ReferralProxy';
      } else if (contract === ContractKey.VxPremiaProxy) {
        contractPath = 'contracts/staking/VxPremiaProxy.sol:VxPremiaProxy';
      } else if (contract === ContractKey.VaultMiningProxy) {
        contractPath =
          'contracts/mining/vaultMining/VaultMiningProxy.sol:VaultMiningProxy';
      } else if (contract === 'PREMIA/USDC-C') {
        contractPath = optionPsProxyPath;
      } else if (contract === 'PREMIA/USDC') {
        contractPath = optionRewardProxyPath;
      } else if (category === 'dualMining') {
        contractPath = dualMiningProxyPath;
      } else if (category === 'vaults' && contract.includes('pSV-')) {
        contractPath = underwriterVaultProxyPath;
      }

      try {
        await verifyContractsOnEtherscan(
          address,
          deploymentArgs,
          libraries,
          contractPath,
        );
      } catch (e) {
        console.log({ address, deploymentArgs, libraries, contractPath });
        console.error(e);
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
