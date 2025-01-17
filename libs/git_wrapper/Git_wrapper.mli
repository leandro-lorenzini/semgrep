(* Small wrapper around the 'git' command-line program *)

(* TODO: make sub capability with cap_git_exec *)

exception Error of string

(* very general helper to run a git command and return its output
 * if everthing went fine or log the error (using Logs) and
 * raise an Error exn otherwise.
 *)
val git_check_output : < Cap.exec > -> Cmd.args -> string

type sha = SHA of string [@@unboxed] [@@deriving show, eq, ord, sexp]

val head : < Cap.exec > -> ?cwd:Fpath.t -> unit -> sha

(*
   This is incomplete. Git offer a variety of filters and subfilters,
   and it would be a lot of work to translate them all into clean types.
   Please extend this interface as needed.
*)
type ls_files_kind =
  | Cached
    (* --cached, the default:
       Show all files cached in Git’s index, i.e. all tracked files *)
  | Others
(* --others:
   Show other (i.e. untracked) files in the output,
   that is mostly the complement of Cached but still
   excluding .git/ *)

(*
   cwd: directory to cd into (-C)

   The argument is the list of files to start scanning from which defaults
   to the current directory.

   This returns a list of paths relative to cwd.
*)
val ls_files :
  ?cwd:Fpath.t ->
  ?exclude_standard:bool ->
  ?kinds:ls_files_kind list ->
  Fpath.t list ->
  Fpath.t list

(*
   This is identical to the 'ls_files' but works even if the current directory
   is outside the git project.

   The result is a list of file paths that are specified relative to the
   current directory (unless it's not possible like on Windows if the
   project is on another volume than the current directory; in that case,
   we return absolute paths).

   The behavior is unspecified if 'project_root' is not the root of a git
   project.
*)
val ls_files_relative :
  ?exclude_standard:bool ->
  ?kinds:ls_files_kind list ->
  project_root:Rpath.t ->
  Fpath.t list ->
  Fpath.t list

(* get merge base between arg and HEAD *)
val get_merge_base : string -> string

(* Executing a function inside a directory created from git-worktree.

   `git worktree` is doing 90% of the heavy lifting here. Docs:
   https://git-scm.com/docs/git-worktree

   In short, git allows you to have multiple working trees checked out at
   the same time. This means you can essentially have X different
   branches/commits checked out from the same repo, in different locations

   Different worktrees share the same .git directory, so this is a lot
   faster/cheaper than cloning the repo multiple times

   This also allows us to not worry about git state, since
   unstaged/staged files are not shared between worktrees. This means we
   don't need to git stash anything, or expect a clean working tree.
*)
val run_with_worktree :
  < Cap.chdir ; Cap.tmp > ->
  commit:string ->
  ?branch:string option ->
  (unit -> 'a) ->
  'a

type status = {
  added : string list;
  modified : string list;
  removed : string list;
  unmerged : string list;
  renamed : (string * string) list;
}
[@@deriving show]

(* git status *)
val status : ?cwd:Fpath.t -> ?commit:string -> unit -> status

(* precondition: cwd must be a directory *)
val is_git_repo : ?cwd:Fpath.t -> unit -> bool
(** Returns true if passed directory a git repo*)

(* Find the root of the repository containing 'cwd', if any.
   The result may be a submodule of another git repo. *)
val get_project_root : ?cwd:Fpath.t -> unit -> Fpath.t option

val checkout : ?cwd:Fpath.t -> ?git_ref:string -> unit -> unit
(** Checkout the given optional ref *)

val sparse_shallow_filtered_checkout : Uri.t -> Fpath.t -> (unit, string) result
(** Checkout the given commit in the given directory, but only
    the files that are tracked by git and that are not in the
    sparse-checkout config.
    This is useful to avoid checking out the whole repo when
    we only need a few files. *)

val sparse_checkout_add : ?cwd:Fpath.t -> Fpath.t list -> (unit, string) result
(** Add the given files to the sparse-checkout config *)

(* Find the root of the git project containing 'cwd', if any.
   The result is not a submodule of another git repo. *)
val get_superproject_root : ?cwd:Fpath.t -> unit -> Fpath.t option

(* precondition: cwd must be a directory *)
val dirty_lines_of_file :
  ?cwd:Fpath.t -> ?git_ref:string -> Fpath.t -> (int * int) array option
(** [dirty_lines_of_file path] will return an optional array of line ranges that indicate what
  * lines have been changed. An optional [git_ref] can be passed that will be used
  * to diff against. The default [git_ref] is ["HEAD"]
  *)

(* precondition: cwd must be a directory *)
val is_tracked_by_git : ?cwd:Fpath.t -> Fpath.t -> bool
(** [is_tracked_by_git path] Returns true if the file is tracked by git *)

(* precondition: cwd must be a directory *)
val dirty_files : ?cwd:Fpath.t -> unit -> Fpath.t list
(** [dirty_files ()] is the list of files which are dirty in a git repo, i.e.,
    files which differ at all from the current index to the HEAD commit, plus
    untracked files. Note that this means this list includes files which were
    deleted. *)

val init : ?cwd:Fpath.t -> ?branch:string -> unit -> unit
(** [init ()] creates an empty git repository in the current directory. If
    [cwd] is specified, its value is passed to git's [-C] flag. If
    [branch] is specified, it is used as the name of the default branch.
    Otherwise the default branch is named 'main' to avoid warnings that depend
    on the git version.

    Initialize a git repo in the given directory.
    The branch is set by default to 'main' to avoid warnings that depend
    on the git version.
*)

val add : ?cwd:Fpath.t -> ?force:bool -> Fpath.t list -> unit
(** [add files] adds the [files] to the git index. *)

val commit : ?cwd:Fpath.t -> string -> unit
(** [commit msg] creates a commit with containing the current contents of the
    index with [msg] as the commit message. *)

val get_project_url : ?cwd:Fpath.t -> unit -> string option
(** [get_project_url ()] tries to get the URL of the project from
    [git ls-remote] or from the [.git/config] file. It returns [None] if it
    found nothing relevant.
    TODO: should maybe raise an exn instead if not run from a git repo.
*)

val get_git_logs : ?cwd:Fpath.t -> ?since:float option -> unit -> string list
(** [get_git_logs ()] will run 'git log' in the current directory
    and returns for each log a JSON string that fits the schema
    defined in semgrep_output_v1.atd contribution type.
    It returns an empty list if it found nothing relevant.
    You can use the [since] parameter to restrict the logs to
    the commits since the specified time.
 *)

type obj_type = Tag | Commit | Tree | Blob [@@deriving show]

(* See <https://git-scm.com/book/en/v2/Git-Internals-Git-Objects> *)
type 'extra obj = { kind : obj_type; sha : sha; extra : 'extra }
[@@deriving show]

type batch_check_extra = { size : int } [@@deriving show]
type batch_extra = { contents : string } [@@deriving show]
type ls_tree_extra = { path : Fpath.t; size : int } [@@deriving show]

val cat_file_batch_check_all_objects :
  ?cwd:Fpath.t -> unit -> batch_check_extra obj list option
(** [cat_file_batch_all_objects ()] will run [git log
   --batch-all-objects --batch-check] in the current working directory (or such
   directory provided by [cwd])

   A batch format sufficient for obtaining the information in
   [batch_check_extra] will be used and that information will be attached to each
   object.
 *)

val cat_file_blob : ?cwd:Fpath.t -> sha -> (string, string) result
(** [cat_file_blob sha] will run [git cat-file blob sha] and return either
    {ul
      {- [Ok contents], where [contents] is the contents of the blob; or}
      {- [Error message] where [message] is a brief message indicating why git
      could not perform the action, e.g., [sha] is not the sha of a blob or
      [sha] does not designate an object.}
    }
 *)

val batch_cat_file_blob :
  ?cwd:Fpath.t ->
  < Cap.tmp > ->
  sha list ->
  ((batch_extra obj, string) result Seq.t, string) result
(** [batch_cat_file_blob blobs] will run [git cat-file --batch] for each blob
    object whose sha is listed in [blobs] and return either:
    {ul
      {- [Ok output], where [output] is a sequence batch output, where the
      elements are either [Ok info], where [info] is the information returned
      about that blob; or [Error message] where [message] is a brief message
      indicating why git could not perform the action in relation to an
      individual blob, e.g., a sha in [blobs] is not the sha of a blob or does
      not designate an object.

      Note that the output Seq must be consumed to prevent a resource leak,
      since this is implemented by saving the results, and then parsing
      additional blobs on-demand. Ideally we would rely on Eio for this, but
      that's currently blocked on 5.x.}
      {- [Error message], where [message] is a brief message indicating why git
      could not perform the entire batch operation, e.g., the directory in
      which git was run is not a git repo.}
    }

    Note: we make no ordering guarantee of objects in the output list relative
    to the order in the input list.
 *)

val object_size : ?cwd:Fpath.t -> sha -> int option
(** [object_size sha] evaluates to [Some s] where [s] is the size of the object
    designated by [sha] in bytes, or [None] if an error occured (e.g. the
    object didn't exist).
  *)

val commit_timestamp : ?cwd:Fpath.t -> sha -> Timedesc.Timestamp.t option
(** [commit_datetime sha] evaluates to [Some dt] where [dt] is the date and
   time of the commit designated by [sha] or [None] if an error occured (e.g.,
   the sha was for another object type).
 *)

val ls_tree :
  ?cwd:Fpath.t -> ?recurse:bool -> sha -> ls_tree_extra obj list option
(** [ls_tree ~recurse sha] will run `git ls-tree --full-tree` and report the
   listed objects and their file paths relative to that tree. If [recurse] is
   specified to be true (it is false by default) then the `-r` option is passed
   and git will recurse into subtrees.
 *)

val remote_repo_name : string -> string option
(** [remote_repo_name "https://github.com/semgrep/semgrep.git"] will return [Some "semgrep"] *)

(*****************************************************************************)
(* For testing *)
(*****************************************************************************)

(*
   Create a temporary git repo for testing purposes, cd into it,
   call a function, tear down the repo, and restore the original cwd.
   This is an extension of Testutil_files.
*)
val with_git_repo : Testutil_files.t list -> (unit -> 'a) -> 'a
