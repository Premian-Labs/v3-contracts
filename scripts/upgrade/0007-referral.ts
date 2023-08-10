import { Referral__factory, ReferralProxy__factory } from '../../typechain';
import arbitrumDeployment from '../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../utils/deployment/arbitrumGoerli.json';
import {
  ChainID,
  ContractKey,
  ContractType,
  DeploymentInfos,
} from '../../utils/deployment/types';
import { ethers } from 'hardhat';
import { updateDeploymentInfos } from '../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let deployment: DeploymentInfos;
  let setImplementation: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    setImplementation = false;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    setImplementation = true;
  } else {
    throw new Error('ChainId not implemented');
  }

  //////////////////////////

  const args = [deployment.PoolFactoryProxy.address];
  const implementation = await new Referral__factory(deployer).deploy(args[0]);
  await updateDeploymentInfos(
    deployer,
    ContractKey.ReferralImplementation,
    ContractType.Implementation,
    implementation,
    args,
    true,
  );

  if (setImplementation) {
    const proxy = ReferralProxy__factory.connect(
      deployment.ReferralProxy.address,
      deployer,
    );
    await proxy.setImplementation(implementation.address);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
