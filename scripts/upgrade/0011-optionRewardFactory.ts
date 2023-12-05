import {
  OptionRewardFactory__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../typechain';
import { ContractKey, ContractType } from '../utils/deployment/types';
import { ethers } from 'hardhat';
import {
  initialize,
  updateDeploymentMetadata,
} from '../utils/deployment/deployment';
import { proposeOrSendTransaction } from '../utils/safe';
import { parseEther } from 'ethers/lib/utils';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, proposeToMultiSig } = await initialize(deployer);

  //////////////////////////

  const defaultOptionRewardFee = parseEther('0.05'); // 5%
  const feeReceiver = deployment.feeConverter.treasury.address;

  const args = [defaultOptionRewardFee.toString(), feeReceiver];

  const implementation = await new OptionRewardFactory__factory(
    deployer,
  ).deploy(args[0], args[1]);

  await updateDeploymentMetadata(
    deployer,
    ContractKey.OptionRewardFactoryImplementation,
    ContractType.Implementation,
    implementation,
    args,
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxy = ProxyUpgradeableOwnable__factory.connect(
    deployment.core.OptionRewardFactoryProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.addresses.treasury,
    proposeToMultiSig ? proposer : deployer,
    [transaction],
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
