import { VxPremia__factory, VxPremiaProxy__factory } from '../../typechain';
import { ethers } from 'hardhat';
import {
  ContractKey,
  ContractType,
  initialize,
  proposeOrSendTransaction,
  updateDeploymentMetadata,
} from '../utils';

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, proposeToMultiSig, proxyManager } = await initialize(
    deployer,
  );

  //////////////////////////

  const args = [
    proxyManager,
    deployment.addresses.lzEndpoint,
    deployment.tokens.PREMIA,
    deployment.tokens.USDC,
    deployment.core.ExchangeHelper.address,
    deployment.core.VaultRegistryProxy.address,
  ];
  const implementation = await new VxPremia__factory(deployer).deploy(
    args[0],
    args[1],
    args[2],
    args[3],
    args[4],
    args[5],
  );
  await updateDeploymentMetadata(
    deployer,
    ContractKey.VxPremiaImplementation,
    ContractType.Implementation,
    implementation,
    args,
    { logTxUrl: true, verification: { enableVerification: true } },
  );

  const proxy = VxPremiaProxy__factory.connect(
    deployment.core.VxPremiaProxy.address,
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
