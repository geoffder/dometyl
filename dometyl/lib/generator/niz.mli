open! Scad_ml

module Bottom : sig
  val w : float
  val h : float
  val thickness : float
  val bulge_thickness : float
  val bulge_length : float
  val bulge_height : float
  val ellipse_offset : float
  val ellipse_inset_x_rad : float
  val ellipse_inset_y_scale : float
  val corner_cut_rad : float
  val corner_cut_off : float
  val ellipse : Scad.d2
  val bulge : Scad.d2
  val cutter : Scad.d2
  val shadow : Scad.d2
  val scad : Scad.d3
end

module Config : sig
  type t =
    { outer_w : float
    ; outer_h : float
    ; inner_w : float
    ; inner_h : float
    ; thickness : float
    ; cap_height : float
    ; cap_cutout_height : float option
    ; clearance : float
    ; corner : Path3.Round.corner option
    ; fn : int option
    ; dome_w : float
    ; dome_waist_clip : float
    ; dome_thickness : float
    ; base_thickness : float
    ; sensor_depth : float
    ; sensor_cutter : Sensor.cutter
    }

  val make
    :  ?outer_w:float
    -> ?outer_h:float
    -> ?inner_w:float
    -> ?inner_h:float
    -> ?thickness:float
    -> ?cap_height:float
    -> ?cap_cutout_height:float option
    -> ?clearance:float
    -> ?corner:Path3.Round.corner
    -> ?fn:int
    -> ?dome_w:float
    -> ?dome_waist_clip:float
    -> ?dome_thickness:float
    -> ?base_thickness:float
    -> ?sensor_depth:float
    -> ?sensor_cutter:Sensor.cutter
    -> unit
    -> t

  val default : t
end

val hole_of_config : ?render:bool -> ?cap:Scad.d3 -> Config.t -> Key.t

val make_hole
  :  ?render:bool
  -> ?cap:Scad.d3
  -> ?outer_w:float
  -> ?outer_h:float
  -> ?inner_w:float
  -> ?inner_h:float
  -> ?thickness:float
  -> ?cap_height:float
  -> ?cap_cutout_height:float option
  -> ?clearance:float
  -> ?corner:Path3.Round.corner
  -> ?fn:int
  -> ?dome_w:float
  -> ?dome_waist_clip:float
  -> ?dome_thickness:float
  -> ?base_thickness:float
  -> ?sensor_depth:float
  -> ?sensor_cutter:Sensor.cutter
  -> unit
  -> Key.t

val empty_hole_of_config : ?render:bool -> ?cap:Scad.d3 -> Config.t -> Key.t

val make_empty_hole
  :  ?render:bool
  -> ?cap:Scad.d3
  -> ?outer_w:float
  -> ?outer_h:float
  -> ?inner_w:float
  -> ?inner_h:float
  -> ?thickness:float
  -> ?cap_height:float
  -> ?cap_cutout_height:float option
  -> ?clearance:float
  -> ?corner:Path3.Round.corner
  -> ?fn:int
  -> unit
  -> Key.t
