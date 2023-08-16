import { Referral__factory, ReferralProxy__factory } from '../../typechain';
import { ContractKey, ContractType } from '../../utils/deployment/types';
import { ethers } from 'hardhat';
import {
  initialize,
  updateDeploymentInfos,
} from '../../utils/deployment/deployment';
import { proposeOrSendTransaction } from '../utils/safe';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, proposeToMultiSig } = await initialize(deployer);

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
    proposer,
    [transaction],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
