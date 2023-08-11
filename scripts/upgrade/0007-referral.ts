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
import { proposeOrSendTransaction } from '../utils/safe';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  //////////////////////////

  let deployment: DeploymentInfos;
  let proposeToMultiSig: boolean;

  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
    proposeToMultiSig = true;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
    proposeToMultiSig = false;
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

  const proxy = ReferralProxy__factory.connect(
    deployment.ReferralProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.treasury,
    deployer,
    [transaction],
    false,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
