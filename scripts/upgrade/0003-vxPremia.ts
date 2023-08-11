import { VxPremia__factory, VxPremiaProxy__factory } from '../../typechain';
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

  let proxyManager: string;
  let lzEndpoint: string;
  let deployment: DeploymentInfos;
  let proposeToMultiSig: boolean;

  if (chainId === ChainID.Arbitrum) {
    proxyManager = '0x89b36CE3491f2258793C7408Bd46aac725973BA2';
    lzEndpoint = '0x3c2269811836af69497E5F486A85D7316753cf62';
    deployment = arbitrumDeployment;
    proposeToMultiSig = true;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    proxyManager = ethers.constants.AddressZero;
    lzEndpoint = ethers.constants.AddressZero;
    deployment = arbitrumGoerliDeployment;
    proposeToMultiSig = false;
  } else {
    throw new Error('ChainId not implemented');
  }

  //////////////////////////

  const args = [
    proxyManager,
    lzEndpoint,
    deployment.tokens.PREMIA,
    deployment.tokens.USDC,
    deployment.ExchangeHelper.address,
    deployment.VaultRegistryProxy.address,
  ];
  const implementation = await new VxPremia__factory(deployer).deploy(
    args[0],
    args[1],
    args[2],
    args[3],
    args[4],
    args[5],
  );
  await updateDeploymentInfos(
    deployer,
    ContractKey.VxPremiaImplementation,
    ContractType.Implementation,
    implementation,
    args,
    true,
  );

  const proxy = VxPremiaProxy__factory.connect(
    deployment.VxPremiaProxy.address,
    deployer,
  );

  const transaction = await proxy.populateTransaction.setImplementation(
    implementation.address,
  );

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.treasury,
    deployer,
    transaction,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
