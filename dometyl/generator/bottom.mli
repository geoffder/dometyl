open! Scad_ml

type bump_loc =
  | Thumb of Util.idx * Util.idx * v2 option
  | Body of Util.idx * Util.idx * v2 option
  | Point of V2.t

val thumb : ?loc:v2 -> Util.idx -> Util.idx -> bump_loc
val body : ?loc:v2 -> Util.idx -> Util.idx -> bump_loc
val point : v2 -> bump_loc
val default_bumps : bump_loc list
val locate_bump : Plate.t -> bump_loc -> V2.t option

val make
  :  ?thickness:float
  -> ?fastener:Eyelet.fastener
  -> ?bumpon_rad:float
  -> ?bumpon_inset:float
  -> ?bump_locs:bump_loc list
  -> Case.t
  -> Scad.d3
