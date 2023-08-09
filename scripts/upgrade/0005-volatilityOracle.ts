import {
  ProxyUpgradeableOwnable,
  ProxyUpgradeableOwnable__factory,
  VolatilityOracle__factory,
} from '../../typechain';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import { ChainID, DeploymentInfos } from '../../utils/deployment/types';
import fs from 'fs';
import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let proxy: ProxyUpgradeableOwnable;
  let deployment: DeploymentInfos;
  let addressesPath: string;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    addressesPath = 'utils/deployment/arbitrum.json';
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    addressesPath = 'utils/deployment/arbitrumGoerli.json';
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  proxy = ProxyUpgradeableOwnable__factory.connect(
    deployment.VolatilityOracleProxy.address,
    deployer,
  );

  //////////////////////////

  const volatilityOracleImpl = await new VolatilityOracle__factory(
    deployer,
  ).deploy();
  await volatilityOracleImpl.deployed();
  console.log(
    `VolatilityOracle implementation : ${volatilityOracleImpl.address}`,
  );

  // Save new addresses
  deployment.VolatilityOracleImplementation.address =
    volatilityOracleImpl.address;
  fs.writeFileSync(addressesPath, JSON.stringify(deployment, null, 2));

  if (setImplementation) {
    await proxy.setImplementation(volatilityOracleImpl.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
