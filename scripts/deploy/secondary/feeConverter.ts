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

  const treasury = deployment.treasury;
  const treasuryShare = parseEther('0.5');

  if (!deployment.FeeConverterImplementation.address) {
    const feeConverterImplArgs = [
      deployment.ExchangeHelper.address,
      deployment.tokens.USDC,
      deployment.VxPremiaProxy.address,
    ];
    const feeConverterImpl = await new FeeConverter__factory(deployer).deploy(
      feeConverterImplArgs[0],
      feeConverterImplArgs[1],
      feeConverterImplArgs[2],
    );
    deployment = await updateDeploymentInfos(
      deployer,
      'FeeConverterImplementation',
      ContractType.Implementation,
      feeConverterImpl,
      feeConverterImplArgs,
      true,
    );
  }

  const feeConverterProxyArgs = [deployment.FeeConverterImplementation.address];
  const feeConverterProxy = await new ProxyUpgradeableOwnable__factory(
    deployer,
  ).deploy(feeConverterProxyArgs[0]);

  const data = await updateDeploymentInfos(
    deployer,
    'FeeConverterProxy',
    ContractType.Proxy,
    feeConverterProxy,
    feeConverterProxyArgs,
    false,
    false,
  );

  const feeConverter = FeeConverter__factory.connect(
    feeConverterProxy.address,
    deployer,
  );
  await feeConverter.setTreasury(treasury, treasuryShare);

  console.log('FeeConverterProxy', (data as any).FeeConverterProxy);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
