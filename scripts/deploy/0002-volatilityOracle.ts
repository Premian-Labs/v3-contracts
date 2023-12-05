import {
  ProxyUpgradeableOwnable__factory,
  VolatilityOracle__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { updateDeploymentMetadata } from '../utils/deployment/deployment';
import { ContractKey, ContractType } from '../utils/deployment/types';

async function main() {
  const [deployer] = await ethers.getSigners();

  const volatilityOracleImplementation = await new VolatilityOracle__factory(
    deployer,
  ).deploy();

  await updateDeploymentMetadata(
    deployer,
    ContractKey.VolatilityOracleImplementation,
    ContractType.Implementation,
    volatilityOracleImplementation,
    [],
    { logTxUrl: true },
  );

  const volatilityOracleProxyArgs = [volatilityOracleImplementation.address];
  const volatilityOracleProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(volatilityOracleProxyArgs[0]);

  await updateDeploymentMetadata(
    deployer,
    ContractKey.VolatilityOracleProxy,
    ContractType.Proxy,
    volatilityOracleProxy,
    volatilityOracleProxyArgs,
    { logTxUrl: true },
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
