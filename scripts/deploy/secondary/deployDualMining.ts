import _ from 'lodash';
import {
  DualMining__factory,
  DualMiningProxy__factory,
  IERC20__factory,
  VaultMining__factory,
} from '../../../typechain';
import { ethers } from 'hardhat';
import { parseEther } from 'ethers/lib/utils';
import { BigNumber, PopulatedTransaction } from 'ethers';
import {
  ContractType,
  DeploymentMetadata,
  initialize,
  updateDeploymentMetadata,
  proposeOrSendTransaction,
} from '../../utils';

interface DualMiningArgs {
  vaultName: string;
  rewardToken: string;
  rewardsPerYear: BigNumber;
  depositAmount: BigNumber;
}

function getName(vaultName: string, deployment: DeploymentMetadata) {
  let i = 1;
  let name = `${vaultName}-${i}`;
  while (_.get(deployment, `dualMining.${name}`)) {
    i++;
    name = `${vaultName}-${i}`;
  }

  return name;
}

async function main() {
  const [deployer, proposer] = await ethers.getSigners();
  const { deployment, proposeToMultiSig } = await initialize(deployer);

  //////////////////////////

  const vaults: DualMiningArgs[] = [
    {
      vaultName: 'pSV-WETH/USDCe-C',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('195640'),
      depositAmount: parseEther('30000'),
    },
    {
      vaultName: 'pSV-WETH/USDCe-P',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('195640'),
      depositAmount: parseEther('30000'),
    },
    {
      vaultName: 'pSV-WBTC/USDCe-C',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('156585'),
      depositAmount: parseEther('24000'),
    },
    {
      vaultName: 'pSV-WBTC/USDCe-P',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('156585'),
      depositAmount: parseEther('24000'),
    },
    {
      vaultName: 'pSV-ARB/USDCe-C',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('117165'),
      depositAmount: parseEther('18000'),
    },
    {
      vaultName: 'pSV-ARB/USDCe-P',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('117165'),
      depositAmount: parseEther('18000'),
    },
    {
      vaultName: 'pSV-PREMIA/USDCe-C',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('45625'),
      depositAmount: parseEther('7000'),
    },
    {
      vaultName: 'pSV-PREMIA/USDCe-P',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('45625'),
      depositAmount: parseEther('7000'),
    },
    {
      vaultName: 'pSV-OP/USDCe-C',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('32485'),
      depositAmount: parseEther('5000'),
    },
    {
      vaultName: 'pSV-OP/USDCe-P',
      rewardToken: deployment.tokens.ARB,
      rewardsPerYear: parseEther('32485'),
      depositAmount: parseEther('5000'),
    },
  ];

  const proposerOrSigner = proposeToMultiSig ? proposer : deployer;
  const transactions: PopulatedTransaction[] = [];

  for (const vault of vaults) {
    const key = getName(vault.vaultName, deployment);

    console.log('------------------');
    console.log(`Deploying ${key}`);

    const vaultAddress = deployment.vaults[vault.vaultName].address;

    const args = [
      deployment.core.DualMiningManager.address,
      vaultAddress,
      vault.rewardToken,
      vault.rewardsPerYear.toString(),
    ];

    const dualMining = await new DualMiningProxy__factory(deployer).deploy(
      args[0],
      args[1],
      args[2],
      args[3],
    );

    await updateDeploymentMetadata(
      deployer,
      `dualMining.${key}`,
      ContractType.Proxy,
      dualMining,
      args,
      { logTxUrl: true },
    );

    const tokenApprovalTx = await IERC20__factory.connect(
      vault.rewardToken,
      proposerOrSigner,
    ).populateTransaction.approve(dualMining.address, vault.depositAmount);

    const addRewardsTx = await DualMining__factory.connect(
      dualMining.address,
      proposerOrSigner,
    ).populateTransaction.addRewards(vault.depositAmount);

    const addDualMiningPoolTx = await VaultMining__factory.connect(
      deployment.core.VaultMiningProxy.address,
      proposerOrSigner,
    ).populateTransaction.addDualMiningPool(vaultAddress, dualMining.address);

    transactions.push(tokenApprovalTx);
    transactions.push(addRewardsTx);
    transactions.push(addDualMiningPoolTx);
  }

  await proposeOrSendTransaction(
    proposeToMultiSig,
    deployment.addresses.treasury,
    proposerOrSigner,
    transactions,
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
