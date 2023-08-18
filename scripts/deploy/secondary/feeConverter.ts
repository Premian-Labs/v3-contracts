import {
  ExchangeHelper__factory,
  FeeConverter__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import { ContractKey, ContractType } from '../../../utils/deployment/types';
import { parseEther } from 'ethers/lib/utils';
import {
  initialize,
  updateDeploymentMetadata,
} from '../../../utils/deployment/deployment';

async function main() {
  const [deployer] = await ethers.getSigners();
  let { deployment } = await initialize(deployer);

  const treasury = deployment.treasury;
  const treasuryShare = parseEther('0.5');

  if (!deployment.ExchangeHelper.address) {
    const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();
    deployment = await updateDeploymentMetadata(
      deployer,
      ContractKey.ExchangeHelper,
      ContractType.Standalone,
      exchangeHelper,
      [],
      true,
    );
  }

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
    deployment = await updateDeploymentMetadata(
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

  const data = await updateDeploymentMetadata(
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
