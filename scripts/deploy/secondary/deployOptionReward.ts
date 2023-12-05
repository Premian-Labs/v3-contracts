import {
  IERC20Metadata__factory,
  OptionRewardFactory__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import { parseEther } from 'ethers/lib/utils';
import {
  ContractType,
  getEvent,
  initialize,
  ONE_DAY,
  updateDeploymentMetadata,
} from '../../utils';

async function main() {
  const [deployer] = await ethers.getSigners();
  const { deployment } = await initialize(deployer);

  //////////////////////////
  // Set those vars to the vault you want to deploy
  const base = deployment.tokens.PREMIA;
  const quote = deployment.tokens.USDC;
  const isCall = true;

  //////////////////////////

  const factory = OptionRewardFactory__factory.connect(
    deployment.core.OptionRewardFactoryProxy.address,
    deployer,
  );

  const tx = await factory[
    'deployProxy((address,address,address,uint256,uint256,uint256,uint256,uint256))'
  ]({
    option: deployment.optionPS['PREMIA/USDC-C'].address,
    oracleAdapter: '',
    paymentSplitter: '',
    percentOfSpot: parseEther('0.55'),
    penalty: parseEther('0.75'),
    optionDuration: 30 * ONE_DAY,
    lockupDuration: 365 * ONE_DAY,
    claimDuration: 365 * ONE_DAY,
  });

  // Used to override fee / feeReceiver (Only callable from owner)
  // const tx = await factory[
  //   'deployProxy((address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,address))'
  // ]({
  //   option: deployment.optionPS['PREMIA/USDC-C'].address,
  //   oracleAdapter: deployment.core.ChainlinkAdapterProxy.address,
  //   paymentSplitter: deployment.core.PaymentSplitterProxy.address,
  //   percentOfSpot: parseEther('0.55'),
  //   penalty: parseEther('0.75'),
  //   optionDuration: 30 * ONE_DAY,
  //   lockupDuration: 365 * ONE_DAY,
  //   claimDuration: 365 * ONE_DAY,
  //   fee: parseEther('0.1'),
  //   feeReceiver: deployment.feeConverter.dao.address,
  // });

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
