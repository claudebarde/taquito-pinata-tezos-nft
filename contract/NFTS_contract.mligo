(**
Implementation of the FA2 interface for the NFT contract supporting multiple
types of NFTs. Each NFT type is represented by the range of token IDs - `token_def`.
 *)

type token_id = nat

type transfer_destination =
[@layout:comb]
{
  to_ : address;
  token_id : token_id;
  amount : nat;
}

type transfer =
[@layout:comb]
{
  from_ : address;
  txs : transfer_destination list;
}

type balance_of_request =
[@layout:comb]
{
  owner : address;
  token_id : token_id;
}

type balance_of_response =
[@layout:comb]
{
  request : balance_of_request;
  balance : nat;
}

type balance_of_param =
[@layout:comb]
{
  requests : balance_of_request list;
  callback : (balance_of_response list) contract;
}

type operator_param =
[@layout:comb]
{
  owner : address;
  operator : address;
  token_id: token_id;
}

type update_operator =
[@layout:comb]
  | Add_operator of operator_param
  | Remove_operator of operator_param

type token_metadata =
[@layout:comb]
{
  token_id : token_id;
  token_info : (string, bytes) map;
}

(*
One of the options to make token metadata discoverable is to declare
`token_metadata : token_metadata_storage` field inside the FA2 contract storage
*)
type token_metadata_storage = (token_id, token_metadata) big_map

(**
Optional type to define view entry point to expose token_metadata on chain or
as an external view
 *)
type token_metadata_param = 
[@layout:comb]
{
  token_ids : token_id list;
  handler : (token_metadata list) -> unit;
}

type mint_params =
[@layout:comb]
{
  link_to_metadata: bytes;
  owner: address;
}

type fa2_entry_points =
  | Transfer of transfer list
  | Balance_of of balance_of_param
  | Update_operators of update_operator list
  | Mint of mint_params
  | Burn of token_id

(* 
 TZIP-16 contract metadata storage field type. 
 The contract storage MUST have a field
 `metadata : contract_metadata`
*)
type contract_metadata = (string, bytes) big_map

(* FA2 hooks interface *)

type transfer_destination_descriptor =
[@layout:comb]
{
  to_ : address option;
  token_id : token_id;
  amount : nat;
}

type transfer_descriptor =
[@layout:comb]
{
  from_ : address option;
  txs : transfer_destination_descriptor list
}

type transfer_descriptor_param =
[@layout:comb]
{
  batch : transfer_descriptor list;
  operator : address;
}

(*
Entrypoints for sender/receiver hooks

type fa2_token_receiver =
  ...
  | Tokens_received of transfer_descriptor_param

type fa2_token_sender =
  ...
  | Tokens_sent of transfer_descriptor_param
*)


(** One of the specified `token_id`s is not defined within the FA2 contract *)
let fa2_token_undefined = "FA2_TOKEN_UNDEFINED" 
(** 
A token owner does not have sufficient balance to transfer tokens from
owner's account 
*)
let fa2_insufficient_balance = "FA2_INSUFFICIENT_BALANCE"
(** A transfer failed because of `operator_transfer_policy == No_transfer` *)
let fa2_tx_denied = "FA2_TX_DENIED"
(** 
A transfer failed because `operator_transfer_policy == Owner_transfer` and it is
initiated not by the token owner 
*)
let fa2_not_owner = "FA2_NOT_OWNER"
(**
A transfer failed because `operator_transfer_policy == Owner_or_operator_transfer`
and it is initiated neither by the token owner nor a permitted operator
 *)
let fa2_not_operator = "FA2_NOT_OPERATOR"
(** 
`update_operators` entrypoint is invoked and `operator_transfer_policy` is
`No_transfer` or `Owner_transfer`
*)
let fa2_operators_not_supported = "FA2_OPERATORS_UNSUPPORTED"
(**
Receiver hook is invoked and failed. This error MUST be raised by the hook
implementation
 *)
let fa2_receiver_hook_failed = "FA2_RECEIVER_HOOK_FAILED"
(**
Sender hook is invoked and failed. This error MUST be raised by the hook
implementation
 *)
let fa2_sender_hook_failed = "FA2_SENDER_HOOK_FAILED"
(**
Receiver hook is required by the permission behavior, but is not implemented by
a receiver contract
 *)
let fa2_receiver_hook_undefined = "FA2_RECEIVER_HOOK_UNDEFINED"
(**
Sender hook is required by the permission behavior, but is not implemented by
a sender contract
 *)
let fa2_sender_hook_undefined = "FA2_SENDER_HOOK_UNDEFINED"
(** 
Reference implementation of the FA2 operator storage, config API and 
helper functions 
*)


(* 
  Permission policy definition. 
  Stored in the TZIP-16 contract metadata JSON
*)

type operator_transfer_policy =
  [@layout:comb]
  | No_transfer
  | Owner_transfer
  | Owner_or_operator_transfer

type owner_hook_policy =
  [@layout:comb]
  | Owner_no_hook
  | Optional_owner_hook
  | Required_owner_hook

type custom_permission_policy =
[@layout:comb]
{
  tag : string;
  config_api: address option;
}

type permissions_descriptor =
[@layout:comb]
{
  operator : operator_transfer_policy;
  receiver : owner_hook_policy;
  sender : owner_hook_policy;
  custom : custom_permission_policy option;
}

(** 
(owner, operator, token_id) -> unit
To be part of FA2 storage to manage permitted operators
*)
type operator_storage = ((address * (address * token_id)), unit) big_map

(** 
  Updates operator storage using an `update_operator` command.
  Helper function to implement `Update_operators` FA2 entrypoint
*)
let update_operators (update, storage : update_operator * operator_storage)
    : operator_storage =
  match update with
  | Add_operator op -> 
    Big_map.update (op.owner, (op.operator, op.token_id)) (Some unit) storage
  | Remove_operator op -> 
    Big_map.remove (op.owner, (op.operator, op.token_id)) storage

(**
Validate if operator update is performed by the token owner.
@param updater an address that initiated the operation; usually `Tezos.sender`.
*)
let validate_update_operators_by_owner (update, updater : update_operator * address)
    : unit =
  let op = match update with
  | Add_operator op -> op
  | Remove_operator op -> op
  in
  if op.owner = updater then unit else failwith fa2_not_owner

(**
  Generic implementation of the FA2 `%update_operators` entrypoint.
  Assumes that only the token owner can change its operators.
 *)
let fa2_update_operators (updates, storage
    : (update_operator list) * operator_storage) : operator_storage =
  let updater = Tezos.sender in
  let process_update = (fun (ops, update : operator_storage * update_operator) ->
    let _u = validate_update_operators_by_owner (update, updater) in
    update_operators (update, ops)
  ) in
  List.fold process_update updates storage

(** 
  owner * operator * token_id * ops_storage -> unit
*)
type operator_validator = (address * address * token_id * operator_storage)-> unit

(**
Create an operator validator function based on provided operator policy.
@param tx_policy operator_transfer_policy defining the constrains on who can transfer.
@return (owner, operator, token_id, ops_storage) -> unit
 *)
let make_operator_validator (tx_policy : operator_transfer_policy) : operator_validator =
  let can_owner_tx, can_operator_tx = match tx_policy with
  | No_transfer -> (failwith fa2_tx_denied : bool * bool)
  | Owner_transfer -> true, false
  | Owner_or_operator_transfer -> true, true
  in
  (fun (owner, operator, token_id, ops_storage 
      : address * address * token_id * operator_storage) ->
    if can_owner_tx && owner = operator
    then unit (* transfer by the owner *)
    else if not can_operator_tx
    then failwith fa2_not_owner (* an operator transfer not permitted by the policy *)
    else if Big_map.mem  (owner, (operator, token_id)) ops_storage
    then unit (* the operator is permitted for the token_id *)
    else failwith fa2_not_operator (* the operator is not permitted for the token_id *)
  )

(**
Default implementation of the operator validation function.
The default implicit `operator_transfer_policy` value is `Owner_or_operator_transfer`
 *)
let default_operator_validator : operator_validator =
  (fun (owner, operator, token_id, ops_storage 
      : address * address * token_id * operator_storage) ->
    if owner = operator
    then unit (* transfer by the owner *)
    else if Big_map.mem (owner, (operator, token_id)) ops_storage
    then unit (* the operator is permitted for the token_id *)
    else failwith fa2_not_operator (* the operator is not permitted for the token_id *)
  )

(** 
Validate operators for all transfers in the batch at once
@param tx_policy operator_transfer_policy defining the constrains on who can transfer.
*)
let validate_operator (tx_policy, txs, ops_storage 
    : operator_transfer_policy * (transfer list) * operator_storage) : unit =
  let validator = make_operator_validator tx_policy in
  List.iter (fun (tx : transfer) -> 
    List.iter (fun (dst: transfer_destination) ->
      validator (tx.from_, Tezos.sender, dst.token_id ,ops_storage)
    ) tx.txs
  ) txs

(* range of nft tokens *)
type token_def =
[@layout:comb]
{
  from_ : nat;
  to_ : nat;
}

type nft_meta = (token_def, token_metadata) big_map

type token_storage = {
  token_defs : token_def set;
  next_token_id : token_id;
  metadata : nft_meta;
}

type ledger = (token_id, address) big_map
type reverse_ledger = (address, token_id list) big_map

type nft_token_storage = {
  ledger : ledger;
  operators : operator_storage;
  reverse_ledger: reverse_ledger;
  metadata: (string, bytes) big_map;
  token_metadata: token_metadata_storage;
  next_token_id: token_id;
  admin: address;
}

(** 
Retrieve the balances for the specified tokens and owners
@return callback operation
*)
let get_balance (p, ledger : balance_of_param * ledger) : operation =
  let to_balance = fun (r : balance_of_request) ->
    let owner = Big_map.find_opt r.token_id ledger in
    match owner with
    | None -> (failwith fa2_token_undefined : balance_of_response)
    | Some o ->
      let bal = if o = r.owner then 1n else 0n in
      { request = r; balance = bal; }
  in
  let responses = List.map to_balance p.requests in
  Tezos.transaction responses 0mutez p.callback

(**
Update leger balances according to the specified transfers. Fails if any of the
permissions or constraints are violated.
@param txs transfers to be applied to the ledger
@param validate_op function that validates of the tokens from the particular owner can be transferred. 
 *)
let transfer (txs, validate_op, ops_storage, ledger, reverse_ledger
    : (transfer list) * operator_validator * operator_storage * ledger * reverse_ledger) : ledger * reverse_ledger =
  (* process individual transfer *)
  let make_transfer = (fun ((l, rv_l), tx : (ledger * reverse_ledger) * transfer) ->
    List.fold 
      (fun ((ll, rv_ll), dst : (ledger * reverse_ledger) * transfer_destination) ->
        if dst.amount = 0n
        then ll, rv_ll
        else if dst.amount <> 1n
        then (failwith fa2_insufficient_balance : ledger * reverse_ledger)
        else
          let owner = Big_map.find_opt dst.token_id ll in
          match owner with
          | None -> (failwith fa2_token_undefined : ledger * reverse_ledger)
          | Some o -> 
            if o <> tx.from_
            then (failwith fa2_insufficient_balance : ledger * reverse_ledger)
            else 
              begin
                let _u = validate_op (o, Tezos.sender, dst.token_id, ops_storage) in
                let new_ll = Big_map.update dst.token_id (Some dst.to_) ll in
                (* removes token id from sender *)
                let new_rv_ll = 
                  match Big_map.find_opt tx.from_ rv_ll with
                  | None -> (failwith fa2_insufficient_balance : reverse_ledger)
                  | Some tk_id_l -> 
                      Big_map.update 
                        tx.from_ 
                        (Some (List.fold (
                          fun (new_list, token_id: token_id list * token_id) ->
                            if token_id = dst.token_id
                            then new_list
                            else token_id :: new_list
                        ) tk_id_l ([]: token_id list))) 
                        rv_ll 
                in
                (* adds token id to recipient *)
                let updated_rv_ll = 
                  match Big_map.find_opt dst.to_ new_rv_ll with
                  | None -> Big_map.add dst.to_ [dst.token_id] new_rv_ll
                  | Some tk_id_l -> Big_map.update dst.to_ (Some (dst.token_id :: tk_id_l)) new_rv_ll in

                new_ll, updated_rv_ll
              end
      ) tx.txs (l, rv_l)
  )
  in 
    
  List.fold make_transfer txs (ledger, reverse_ledger)

(** Finds a definition of the token type (token_id range) associated with the provided token id *)
let find_token_def (tid, token_defs : token_id * (token_def set)) : token_def =
  let tdef = Set.fold (fun (res, d : (token_def option) * token_def) ->
    match res with
    | Some _ -> res
    | None ->
      if tid >= d.from_ && tid < d.to_
      then  Some d
      else (None : token_def option)
  ) token_defs (None : token_def option)
  in
  match tdef with
  | None -> (failwith fa2_token_undefined : token_def)
  | Some d -> d

let get_metadata (tokens, meta : (token_id list) * token_storage )
    : token_metadata list =
  List.map (fun (tid: token_id) ->
    let tdef = find_token_def (tid, meta.token_defs) in
    let meta = Big_map.find_opt tdef meta.metadata in
    match meta with
    | Some m -> { m with token_id = tid; }
    | None -> (failwith "NO_DATA" : token_metadata)
  ) tokens

let mint (p, s: mint_params * nft_token_storage): nft_token_storage =
  let { link_to_metadata; owner } = p in
  let token_id = s.next_token_id in
  (* Updates the ledger *)
  let new_ledger = Big_map.add token_id owner s.ledger in
  (* Updates the reverse ledger *)
  let new_reverse_ledger = 
    match Big_map.find_opt owner s.reverse_ledger with
    | None -> Big_map.add owner [token_id] s.reverse_ledger
    | Some l -> Big_map.update owner (Some (token_id :: l)) s.reverse_ledger in
  (* Stores the metadata *)
  let new_entry = { token_id = token_id; token_info = Map.literal [("", link_to_metadata)] } in
  
  { 
      s with 
          ledger = new_ledger;
          reverse_ledger = new_reverse_ledger;
          token_metadata = Big_map.add token_id new_entry s.token_metadata;
          next_token_id = token_id + 1n;
  }

let burn (p, s: token_id * nft_token_storage): nft_token_storage =
  (* removes token from the ledger *)
  let new_ledger: ledger =
    match Big_map.find_opt p s.ledger with
    | None -> (failwith "UNKNOWN_TOKEN": ledger)
    | Some owner ->
      if owner <> Tezos.sender
      then (failwith "NOT_TOKEN_OWNER": ledger)
      else
        Big_map.remove p s.ledger
  in
  (* removes token from the reverse ledger *)
  let new_reverse_ledger: reverse_ledger =
    match Big_map.find_opt Tezos.sender s.reverse_ledger with
    | None -> (failwith "NOT_A_USER": reverse_ledger)
    | Some tk_id_l -> 
      Big_map.update 
        Tezos.sender 
        (Some (List.fold (
          fun (new_list, token_id: token_id list * token_id) ->
            if token_id = p
            then new_list
            else token_id :: new_list
        ) tk_id_l ([]: token_id list))) 
        s.reverse_ledger
  in { s with ledger = new_ledger; reverse_ledger = new_reverse_ledger }

let fa2_main (param, storage : fa2_entry_points * nft_token_storage)
    : (operation  list) * nft_token_storage =
  match param with
  | Transfer txs ->
    let (new_ledger, new_reverse_ledger) = transfer 
      (txs, default_operator_validator, storage.operators, storage.ledger, storage.reverse_ledger) in
    let new_storage = { storage with ledger = new_ledger; reverse_ledger = new_reverse_ledger } in
    ([] : operation list), new_storage

  | Balance_of p ->
    let op = get_balance (p, storage.ledger) in
    [op], storage

  | Update_operators updates ->
    let new_ops = fa2_update_operators (updates, storage.operators) in
    let new_storage = { storage with operators = new_ops; } in
    ([] : operation list), new_storage

  | Mint p ->
    ([]: operation list), mint (p, storage)

  | Burn p ->
    ([]: operation list), burn (p, storage)


(*

{
  ledger = (Big_map.empty: (token_id, address) big_map);
  operators = (Big_map.empty: ((address * (address * token_id)), unit) big_map);
  reverse_ledger = (Big_map.empty: (address, token_id list) big_map);
  metadata = Big_map.literal [
  ("", Bytes.pack("tezos-storage:contents"));
  ("contents", ("7b2276657273696f6e223a2276312e302e30222c226e616d65223a2254555473222c22617574686f7273223a5b2240636c617564656261726465225d2c22696e7465726661636573223a5b22545a49502d303132222c22545a49502d303136225d7d": bytes))
  ];
  token_metadata = (Big_map.empty: (token_id, token_metadata) big_map);
  next_token_id = 0n;
  admin = ("tz1Me1MGhK7taay748h4gPnX2cXvbgL6xsYL": address);
}

{"version":"v1.0.0","name":"TUTs","authors":["@claudebarde"],"interfaces":["TZIP-012","TZIP-016"]}


*)