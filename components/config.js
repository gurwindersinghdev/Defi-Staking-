import { createWalletClient, custom } from "viem";
import { sepolia } from "viem/chains";
import guardianAbi from "./guardian.json";
import tokenAbi from "./erc20abi.json";
import { ethers } from "ethers";

const guardianAddr = "0xdaF9680d4e909B1aFb28b3Fac3A223535f1B6ADf";

// Request Ethereum account access from the user.
const web3Provider = async () => {
  const [account] = await window.ethereum.request({
    method: "eth_requestAccounts",
  });

  // Create a wallet client with the user's account and Ethereum provider
  const client = createWalletClient({
    account,
    chain: sepolia,
    transport: custom(window.ethereum),
  });
  return client;
};

// Convert value to Ethereum (ETH) format.
const convertToEth = async (type, value) => {
  if (type == "reward") {
    // For reward, format with 8 decimal places.
    return Number(ethers.utils.formatEther(value)).toFixed("8");
  } else {
    // For other types, format with 2 decimal places.
    return Number(ethers.utils.formatEther(value)).toFixed("2");
  }
};

const convertToWei = async (value) => {
  return ethers.utils.parseEther(value);
};

// Connect to the user's Ethereum wallet.
export async function connectWallet() {
  // Establish a connection with the user's wallet.
  const connection = await web3Provider();
  // Create an Ethereum provider and signer using the connection.
  const provider = new ethers.providers.Web3Provider(connection);
  const signer = provider.getSigner();
  // Create a contract instance for a 'guardian' using its address and ABI.
  const guardian = new ethers.Contract(guardianAddr, guardianAbi, signer);
  return { connection, signer, guardian, guardianAddr };
}

// Fetch the token balances for the 'pool' and 'user'.
export const fetchTokenBalance = async (tokenaddress, userwallet) => {
  // Connect to the user's Ethereum wallet.
  const web3connection = await connectWallet();

  // Create a contract instance for the token using its address and ABI
  const tokencontract = new ethers.Contract(
    tokenaddress,
    tokenAbi,
    web3connection.signer
  );
  // Fetch the balance of the 'pool' and convert it to Ether.
  let poolBalance = await tokencontract.balanceOf(guardianAddr);
  let pool = await convertToEth(null, poolBalance);
  // Fetch the user's balance and convert it to Ether.
  let userBalance = await tokencontract.balanceOf(userwallet);
  let user = await convertToEth(null, userBalance);
  return { pool, user };
};

// Fetch details of available pools.
export const getPoolDetails = async () => {
  // Connect to the user's Ethereum wallet.
  let web3connection = await connectWallet();
  // Obtain the user's wallet address.
  let userwallet = web3connection.connection.account.address;
  // Access the 'guardian' contract.
  let guardian = web3connection.guardian;
  // Determine the number of pools available.
  let poolLength = Number((await guardian.poolLength()).toString());
  let poolArray = [];

  // Iterate through each pool to collect pool information.
  for (let i = 0; i < poolLength; i++) {
    // Fetch information about the specific pool.
    let poolInfo = await guardian.poolInfo(i);

    // Extract the token address associated with the pool from the pool information.
    let tokenAddress = poolInfo[0];

    // Get the raw reward per token value from the pool information
    let rewardPerTokenRaw = poolInfo[3].toString();

    // Convert the reward per token to Ether format
    let rewardPerToken = Number(
      await convertToEth("reward", rewardPerTokenRaw)
    );
    // Fetch token balances and user-specific data.
    let tokenbalances = await fetchTokenBalance(tokenAddress, userwallet);
    let userStakedArray = await guardian.userInfo(i, userwallet);

    // Get the raw user reward amount (presumably pending rewards)
    let userRewardRaw = (
      await guardian.pendingReward(i, userwallet)
    ).toString();

    // Obtain the bonus multiplier.
    let bonus = (await guardian.BONUS_MULTIPLIER()).toString();

    // Convert the user reward to Ether format with two decimal places.
    let userReward = Number(
      await convertToEth("reward", userRewardRaw)
    ).toFixed("2");

    // Convert the user staked amount to Ether format with two decimal places.
    let userStaked = Number(
      await convertToEth("reward", userStakedArray["amount"].toString())
    ).toFixed("2");
    // Calculate the Annual Percentage Rate (APR).
    let APR = (1000 * rewardPerToken * 100).toFixed("3");
    let poolstats = {
      totalstaked: tokenbalances.pool,
      apy: APR,
      userstaked: userStaked,
      reward: userReward,
      multiplier: bonus,
      userbalance: tokenbalances.user,
      tokenaddr: tokenAddress,
    };
    // Add the pool statistics to the array.
    poolArray.push(poolstats);
  }
  // Return an array of pool details.
  return poolArray;
};

// Perform an action such as stake or unstake in a pool.
export const action = async (i, amount, tokenaddress, action) => {
  try {
    // Convert the specified amount to Wei.
    let amountToWei = (await convertToWei(amount)).toString();

    // Connect to the user's Ethereum wallet.
    let web3connection = await connectWallet();

    // Access the "guardian" contract.
    let guardian = web3connection.guardian;

    // Get the address of the "guardian" contract.
    let guardianAddr = web3connection.guardianAddr;

    if (action == "unstake") {
      // Unstake tokens from the specified pool.
      let result = await guardian.unstake(i, amountToWei).then(() => {
        return true;
      });
      return result;
    } else if (action == "stake") {
      // If the action is to stake, create a contract instance for the token and approve the transfer.
      const tokencontract = new ethers.Contract(
        tokenaddress,
        tokenAbi,
        web3connection.signer
      );
      let approveTransfer = await tokencontract.approve(
        guardianAddr,
        amountToWei
      );
      let waitApproval = await approveTransfer.wait();
      if (waitApproval) {
        // Stake tokens in the specified pool.
        let result = await guardian.stake(i, amountToWei).then(() => {
          return true;
        });
        return result;
      }
    }
  } catch {
    // Handle errors, if any.
    console.log("error");
  }
};

export const autoCompound = async () => {
  let web3connection = await connectWallet();
  let guardian = web3connection.masterchef;
  let result = await guardian.autoCompound().then(() => {
    return true;
  });
  return result;
};
