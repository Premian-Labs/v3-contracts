import { ContractKey } from '../utils/deployment/types';
import {
  initialize,
  verifyContractsOnEtherscan,
} from '../utils/deployment/deployment';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  for (const el in deployment.core) {
    console.log(`Verifying ${el}`);
    const contract = el as ContractKey;
    const { address, deploymentArgs } = deployment.core[contract];
    if (!address) continue;

    let libraries = {};
    let contractPath: string | undefined;

    if (contract === ContractKey.UnderwriterVaultImplementation) {
      libraries = {
        OptionMathExternal: deployment.core.OptionMathExternal.address,
      };
    } else if (contract === ContractKey.ChainlinkAdapterProxy) {
      contractPath =
        'contracts/proxy/ProxyUpgradeableOwnable.sol:ProxyUpgradeableOwnable';
    } else if (contract === ContractKey.PoolFactoryProxy) {
      contractPath = 'contracts/factory/PoolFactoryProxy.sol:PoolFactoryProxy';
    } else if (contract === ContractKey.UserSettingsProxy) {
      contractPath =
        'contracts/proxy/ProxyUpgradeableOwnable.sol:ProxyUpgradeableOwnable';
    } else if (contract === ContractKey.ReferralProxy) {
      contractPath = 'contracts/referral/ReferralProxy.sol:ReferralProxy';
    } else if (contract === ContractKey.VxPremiaProxy) {
      contractPath = 'contracts/staking/VxPremiaProxy.sol:VxPremiaProxy';
    } else if (contract === ContractKey.VaultRegistryProxy) {
      contractPath =
        'contracts/proxy/ProxyUpgradeableOwnable.sol:ProxyUpgradeableOwnable';
    } else if (contract === ContractKey.VolatilityOracleProxy) {
      contractPath =
        'contracts/proxy/ProxyUpgradeableOwnable.sol:ProxyUpgradeableOwnable';
    } else if (contract === ContractKey.VaultMiningProxy) {
      contractPath =
        'contracts/mining/vaultMining/VaultMiningProxy.sol:VaultMiningProxy';
    } else if (contract === ContractKey.OptionPSFactoryProxy) {
      contractPath =
        'contracts/mining/optionPS/OptionPSFactory.sol:OptionPSFactory';
    } else if (contract === ContractKey.OptionRewardFactoryProxy) {
      contractPath =
        'contracts/mining/optionReward/OptionRewardFactory.sol:OptionRewardFactory.sol';
    }

    await verifyContractsOnEtherscan(
      address,
      deploymentArgs,
      libraries,
      contractPath,
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
