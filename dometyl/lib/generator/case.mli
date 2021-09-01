(** Top-level module of this generator library. Used to tie together each of
    the major components of the case:
- The switch-{!Plate.t} made up by columns of {!KeyHole.t}
- The {!Walls.t} from columns/thumb cluster to the ground
- The connections between the separate walls provided by {!module:Connect} *)

open! Base
open! Scad_ml

(** The top-level type of this library. The {!Model.t} scad held within this type
    should generally represent the finished case, made up of the three major building
    blocks: {!Plate.t}, {!Walls.t}, and {!Connect.t}. *)
type 'k t =
  { scad : Model.t
  ; plate : 'k Plate.t
  ; walls : Walls.t
  ; connections : Connect.t
  }

(** Basic transformation functions, applied to all relevant non-config contents. *)
include Sigs.Transformable' with type 'k t := 'k t

(** [make ~plate_welder ~wall_builder ~base_connector ~ports_cutter plate]

A high level helper used to contsruct the case from provided functions and a {!Plate.t}.
- [plate_welder] function intended to generate a {!Model.t} that provides support
  between columns.
- [wall_builder] uses the provided {!Plate.t} to create {!Walls.t} from the ends and
  sides of the columns to the ground (likely a closure using {!Walls.Body.make}
  and {!Walls.Thumb.make}).
- [base_connector] connects the walls around the perimeter of the case, using various
  functions provided by {!module:Connect}. This function should return a {!Connect.t} that
  follows along the entire edge of the case in clockwise fashion without gaps. This way
  the resulting {!Case.t} will contain the necessary information to use {!module:Bottom}
  and {!module:Tent}. See {!Connect.skeleton} and {!Connect.closed} for examples that
  provide this functionality.
- [ports_cutter] is intended to be a function that uses {!Walls.t} to create a
  {!Model.t} scad to cut from the case to facilitate placement of jacks/ports. See
  {!Ports.make} for an example of such a function, which can be configured then passed
  as a closure as this parameter. *)
val make
  :  plate_welder:('k Plate.t -> Model.t)
  -> wall_builder:('k Plate.t -> Walls.t)
  -> base_connector:(Walls.t -> Connect.t)
  -> ports_cutter:(Walls.t -> Model.t)
  -> 'k Plate.t
  -> 'k t

(** [to_scad ?show_caps ?show_cutouts]

    Extract the contained {!Model.t}, optionally tacking on keycaps and case
    cutouts (such as representations of hotswap sockets, that are used to
    provide clearance), stored in {!KeyHole.t} with [show_caps] and
    [show_cutouts] respectively. I would recommend against rendering with these
    options active, as they will balloon the processing time, remove the
    colouration only visible in preview mode, and they are not something that
    you will want and stl of anyway. *)
val to_scad : ?show_caps:bool -> ?show_cutouts:bool -> 'k t -> Model.t