import {
  PremiaAirdrip__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import {
  ContractType,
  initialize,
  updateDeploymentMetadata,
} from '../../utils';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  const implementationArgs = [deployment.tokens['PREMIA']];
  const implementation = await new PremiaAirdrip__factory(deployer).deploy(
    implementationArgs[0],
  );

  await updateDeploymentMetadata(
    deployer,
    'premiaAirdrip.PremiaAirdripImplementation',
    ContractType.Implementation,
    implementation,
    implementationArgs,
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxyArgs = [implementation.address];
  const proxy = await new ProxyUpgradeableOwnable__factory(deployer).deploy(
    proxyArgs[0],
  );

  await updateDeploymentMetadata(
    deployer,
    'premiaAirdrip.PremiaAirdripProxy',
    ContractType.Proxy,
    proxy,
    proxyArgs,
    { logTxUrl: true },
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
