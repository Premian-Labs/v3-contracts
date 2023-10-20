import {
  IERC20Metadata__factory,
  OptionPSFactory__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import {
  initialize,
  updateDeploymentMetadata,
} from '../../../utils/deployment/deployment';
import { getEvent } from '../../../utils/events';
import { ContractType } from '../../../utils/deployment/types';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  //////////////////////////
  // Set those vars to the vault you want to deploy
  const base = deployment.tokens.PREMIA;
  const quote = deployment.tokens.USDC;
  const isCall = true;

  //////////////////////////

  const factory = OptionPSFactory__factory.connect(
    deployment.core.OptionPSFactoryProxy.address,
    deployer,
  );

  const tx = await factory.deployProxy({ base, quote, isCall });
  const event = await getEvent(tx, 'ProxyDeployed');

  //

  let baseSymbol = await IERC20Metadata__factory.connect(
    base,
    deployer,
  ).symbol();
  let quoteSymbol = await IERC20Metadata__factory.connect(
    quote,
    deployer,
  ).symbol();

  const name = `${baseSymbol}/${quoteSymbol}-${isCall ? 'C' : 'P'}`;

  const args = [
    deployment.core.OptionPSFactoryProxy.address,
    base,
    quote,
    isCall.toString(),
  ];

  await updateDeploymentMetadata(
    deployer,
    `optionPS.${name}`,
    ContractType.Proxy,
    event[0].args.proxy,
    args,
    { logTxUrl: true, txReceipt: await tx.wait() },
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
