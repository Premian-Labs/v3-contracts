import {
  FeeConverter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';
import arbitrumDeployment from '../../../utils/deployment/arbitrum.json';
import arbitrumGoerliDeployment from '../../../utils/deployment/arbitrumGoerli.json';
import { ethers } from 'hardhat';
import {
  ChainID,
  ContractType,
  DeploymentInfos,
} from '../../../utils/deployment/types';
import { parseEther } from 'ethers/lib/utils';
import { updateDeploymentInfos } from '../../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  const chainId = await deployer.getChainId();

  let deployment: DeploymentInfos;
  if (chainId === ChainID.Arbitrum) {
    deployment = arbitrumDeployment;
  } else if (chainId === ChainID.ArbitrumGoerli) {
    deployment = arbitrumGoerliDeployment;
  } else {
    throw new Error('ChainId not implemented');
  }

  const treasuryShare = parseEther('0.5');

  const feeConverterImplArgs = [
    deployment.ExchangeHelper.address,
    deployment.tokens.USDC,
    deployment.VxPremiaProxy.address,
    deployment.treasury,
    treasuryShare.toString(),
  ];
  const feeConverterImpl = await new FeeConverter__factory(deployer).deploy(
    feeConverterImplArgs[0],
    feeConverterImplArgs[1],
    feeConverterImplArgs[2],
    feeConverterImplArgs[3],
    feeConverterImplArgs[4],
  );

  let data = await updateDeploymentInfos(
    deployer,
    'FeeConverterImplementation',
    ContractType.Implementation,
    feeConverterImpl,
    feeConverterImplArgs,
    false,
    false,
  );

  console.log(
    'FeeConverterImplementation',
    (data as any).FeeConverterImplementation,
  );

  const feeConverterProxyArgs = [feeConverterImpl.address];
  const feeConverterProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(feeConverterProxyArgs[0]);

  data = await updateDeploymentInfos(
    deployer,
    'FeeConverterProxy',
    ContractType.Proxy,
    feeConverterProxy,
    feeConverterProxyArgs,
    false,
    false,
  );

  console.log('FeeConverterProxy', (data as any).FeeConverterProxy);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
