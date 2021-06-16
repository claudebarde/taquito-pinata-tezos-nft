<script lang="ts">
  import { onMount } from "svelte";
  import { TezosToolkit } from "@taquito/taquito";
  import { char2Bytes } from "@taquito/utils";
  import { BeaconWallet } from "@taquito/beacon-wallet";
  import { NetworkType } from "@airgap/beacon-sdk";

  let Tezos: TezosToolkit;
  let wallet: BeaconWallet;
  const walletOptions = {
    name: "Illic et Numquam",
    preferredNetwork: NetworkType.FLORENCENET
  };
  let userAddress: string;
  let files,
    title = "uranus",
    description = "this is Uranus";

  const rpcUrl = "https://api.tez.ie/rpc/florencenet";
  const serverUrl = "http://localhost:8080";
  const contractAddress = "KT18oax6CCuxPyeABm1bF4UaHKPJpc9Jg3DV";
  let pinningMetadata = false;
  let mintingToken = false;
  let newNft:
    | undefined
    | { imageHash: string; metadataHash: string; opHash: string };

  const connect = async () => {
    if (!wallet) {
      wallet = new BeaconWallet(walletOptions);
    }

    try {
      await wallet.requestPermissions({
        network: {
          type: NetworkType.FLORENCENET,
          rpcUrl
        }
      });
      userAddress = await wallet.getPKH();
      console.log(userAddress);
      Tezos.setWalletProvider(wallet);
    } catch (err) {
      console.error(err);
    }
  };

  const disconnect = () => {
    wallet.client.destroy();
    wallet = undefined;
    userAddress = "";
  };

  const upload = async () => {
    try {
      pinningMetadata = true;
      const data = new FormData();
      data.append("image", files[0], "image.png");
      data.append("title", title);
      data.append("description", description);
      data.append("creator", userAddress);

      const response = await fetch(`${serverUrl}/mint`, {
        method: "POST",
        /*headers: {
          "Content-Type": "multipart/form-data"
        },*/
        body: data
      });
      if (response) {
        const data = await response.json();
        console.log(data);
        if (data.status && data.msg.metadataHash && data.msg.imageHash) {
          pinningMetadata = false;
          mintingToken = true;
          // saves NFT on-chain
          const contract = await Tezos.wallet.at(contractAddress);
          const op = await contract.methods
            .mint(char2Bytes("ipfs://" + data.msg.metadataHash), userAddress)
            .send();
          console.log("Op hash:", op.opHash);
          await op.confirmation();

          newNft = {
            imageHash: data.msg.imageHash,
            metadataHash: data.msg.metadataHash,
            opHash: op.opHash
          };

          files = undefined;
          title = "";
          description = "";
        } else {
          throw "No IPFS hash";
        }
      } else {
        throw "No response";
      }
    } catch (error) {
      console.log(error);
    } finally {
      pinningMetadata = false;
      mintingToken = false;
    }
  };

  onMount(async () => {
    Tezos = new TezosToolkit(rpcUrl);
    wallet = new BeaconWallet(walletOptions);
    if (await wallet.client.getActiveAccount()) {
      userAddress = await wallet.getPKH();
      Tezos.setWalletProvider(wallet);
    }
  });
</script>

<style lang="scss">
  $tezos-blue: #2e7df7;

  h1 {
    font-size: 3rem;
    font-family: "Roman-SD";
  }

  button {
    padding: 20px;
    font-size: 1rem;
    border: solid 3px #d1d5db;
    background-color: #e5e7eb;
    border-radius: 10px;
    cursor: pointer;
  }

  .roman {
    text-transform: uppercase;
    font-family: "Roman-SD";
    font-weight: bold;
  }

  .container {
    font-size: 1.3rem;
    & > div {
      padding: 20px;
    }

    label {
      display: flex;
      flex-direction: column;
      text-align: left;
    }

    input,
    textarea {
      padding: 10px;
    }
  }
</style>

<main>
  <div class="container">
    <h1>Illic Et Numquam</h1>
    {#if userAddress}
      <div>
        <button class="roman" on:click={disconnect}>Disconnect</button>
      </div>
      {#if newNft}
        <div>Your NFT has been successfully minted!</div>
        <div>
          <a
            href={`https://cloudflare-ipfs.com/ipfs/${newNft.imageHash}`}
            target="_blank"
            rel="noopener noreferrer nofollow"
          >
            Link to your picture
          </a>
        </div>
        <div>
          <a
            href={`https://cloudflare-ipfs.com/ipfs/${newNft.metadataHash}`}
            target="_blank"
            rel="noopener noreferrer nofollow"
          >
            Link to your metadata
          </a>
        </div>
        <div>
          <a
            href={`https://better-call.dev/edo2net/opg/${newNft.opHash}/contents `}
            target="_blank"
            rel="noopener noreferrer nofollow"
          >
            Link to the operation details
          </a>
        </div>
        <div>
          <button class="roman" on:click={() => (newNft = undefined)}>
            Mint a new NFT
          </button>
        </div>
      {:else}
        <div>
          <div>Select your picture</div>
          <br />
          <input type="file" bind:files />
        </div>
        <div>
          <label for="image-title">
            <span>Title:</span>
            <input type="text" id="image-title" bind:value={title} />
          </label>
        </div>
        <div>
          <label for="image-description">
            <span>Description:</span>
            <textarea
              id="image-description"
              rows="4"
              bind:value={description}
            />
          </label>
        </div>
        <div>
          <button class="roman" on:click={upload}>
            {#if pinningMetadata}
              Saving your image...
            {:else if mintingToken}
              Minting your NFT...
            {:else}
              Upload
            {/if}
          </button>
        </div>
      {/if}
    {:else}
      <div class="roman">Create a NFT with your pictures</div>
      <button class="roman" on:click={connect}>Connect your wallet</button>
    {/if}
  </div>
</main>
