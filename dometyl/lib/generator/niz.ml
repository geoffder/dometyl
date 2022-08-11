open! Base
open! Scad_ml

module Bottom = struct
  let w = 17.5
  let h = 17.5
  let thickness = 4.
  let bulge_thickness = 0.5
  let bulge_length = 6.5
  let bulge_height = 3.2
  let ellipse_offset = -0.25
  let ellipse_x = (w /. 2.) +. ellipse_offset
  let ellipse_inset_x_rad = 1.6
  let ellipse_inset_y_scale = 1.2
  let corner_cut_rad = 3.
  let corner_cut_off = 1.

  let ellipse =
    Scad.scale (v2 1. ellipse_inset_y_scale) (Scad.circle ~fn:32 ellipse_inset_x_rad)

  let bulge = Scad.square ~center:true (v2 bulge_length (bulge_thickness +. 0.1))
  let cutter = Scad.circle ~fn:64 corner_cut_rad

  let corner x_sign y_sign =
    let x = (w /. 2.) +. corner_cut_off
    and y = (h /. 2.) +. corner_cut_off in
    Scad.translate (v2 (x *. x_sign) (y *. y_sign)) cutter

  let shadow =
    Scad.union
      [ Scad.difference
          (Scad.square ~center:true (v2 w h))
          [ Scad.translate (v2 ellipse_x 0.) ellipse
          ; Scad.translate (v2 (ellipse_x *. -1.) 0.) ellipse
          ; corner 1. 1.
          ; corner 1. (-1.)
          ; corner (-1.) 1.
          ; corner (-1.) (-1.)
          ]
      ; Scad.ytrans ((h /. 2.) +. (bulge_thickness /. 2.)) bulge
      ; Scad.ytrans ((h /. -2.) -. (bulge_thickness /. 2.) +. 0.001) bulge
      ]

  let scad =
    let bulges =
      let b = Scad.linear_extrude ~height:bulge_height bulge in
      [ Scad.translate (v3 (bulge_length /. -2.) ((h /. 2.) -. 0.1) 0.) b
      ; Scad.translate (v3 (bulge_length /. -2.) ((h /. -2.) +. 0.1) 0.) b
      ]
    in
    Scad.difference
      (Scad.square ~center:true (v2 w h))
      [ Scad.xtrans ellipse_x ellipse
      ; Scad.xtrans (ellipse_x *. -1.) ellipse
      ; corner 1. 1.
      ; corner 1. (-1.)
      ; corner (-1.) 1.
      ; corner (-1.) (-1.)
      ]
    |> Scad.linear_extrude ~height:(thickness +. 0.001)
    |> fun b -> Scad.union (b :: bulges)
end

module Config = struct
  type t =
    { outer_w : float
    ; outer_h : float
    ; inner_w : float
    ; inner_h : float
    ; thickness : float
    ; cap_height : float
    ; cap_cutout_height : float option
    ; clearance : float
    ; dome_w : float
    ; dome_waist_clip : float
    ; dome_thickness : float
    ; base_thickness : float
    ; sensor_depth : float
    ; sensor_cutter : Sensor.cutter
    }

  let make
      ?(outer_w = 20.5)
      ?(outer_h = 20.5)
      ?(inner_w = 14.)
      ?(inner_h = 14.)
      ?(thickness = 5.6)
      ?(cap_height = 6.5)
      ?(cap_cutout_height = Some 1.5)
      ?(clearance = 4.)
      ?(dome_w = 19.5)
      ?(dome_waist_clip = 1.)
      ?(dome_thickness = 1.6)
      ?(base_thickness = 3.)
      ?(sensor_depth = 1.4)
      ?(sensor_cutter = Sensor.ThroughHole.tape_cutout ())
      ()
    =
    { outer_w
    ; outer_h
    ; inner_w
    ; inner_h
    ; thickness
    ; cap_height
    ; cap_cutout_height
    ; clearance
    ; dome_w
    ; dome_waist_clip
    ; dome_thickness
    ; base_thickness
    ; sensor_depth
    ; sensor_cutter
    }

  let default = make ()
end

(* Dome thickness
    - BKE ~= 0.85mm
    - DES ~= 0.70mm
   The actual value for [dome_thickness] though must account for FDM overhang
   tolerance, thus it should be a good amount higher to ensure reliable fit.

   Both BKE and DES domes are roughly ~19x19mm. *)

(* Magnet size, with a sensor depth of 1.4mm (slightly below the thickness of a
     standard through-hole sensor package):
   - 3x1mm magnets actuate the AH3574 sensor at ~1.16mm travel and are able to
    deactivate by the top of the return with Niz rings
   - 2x1 magnets actuate the AH3572 sensor at ~2.4mm travel, deactivation
    occurs by the top of the return with Niz rings.

   - recommended: 2x1 magnet with sensor_depth = 1.4. Easier to attach magnet
     size, and should be no worries about hysteresis within FDM and gluing
     tolerances with the stock Niz silencing rings. Thinner rings (or no rings)
     will increase the travel, so keep that in mind. *)

(* TODO: better magnet / sensor break down notes *)

let hole_of_config
    ?render
    ?cap
    Config.
      { outer_w
      ; outer_h
      ; inner_w
      ; inner_h
      ; thickness
      ; cap_height
      ; cap_cutout_height
      ; clearance
      ; dome_w
      ; dome_waist_clip
      ; dome_thickness
      ; base_thickness
      ; sensor_depth
      ; sensor_cutter
      }
  =
  let thickness = Float.max thickness (Bottom.thickness +. dome_thickness) in
  let clearance = Float.max clearance (base_thickness +. 0.5)
  and bottom_z = (thickness /. 2.) -. Bottom.thickness
  and bottom_cut = Scad.linear_extrude ~height:(Bottom.thickness *. 2.) Bottom.shadow in
  let dome_z = bottom_z -. dome_thickness in
  let dome_cut =
    let waist_clip sign =
      Scad.difference
        Bottom.ellipse
        [ Scad.square
            ~center:true
            (v2
               (dome_waist_clip *. 2.)
               (Bottom.ellipse_inset_x_rad *. Bottom.ellipse_inset_y_scale *. 2.) )
          |> Scad.translate (v2 (Bottom.ellipse_inset_x_rad *. -.sign) 0.)
        ]
      |> Scad.translate (v2 (Bottom.ellipse_x *. sign) 0.)
    in
    Scad.difference
      (Scad.square ~center:true (v2 dome_w dome_w))
      [ waist_clip 1.; waist_clip (-1.) ]
    |> Scad.linear_extrude ~height:(dome_thickness +. 0.001)
    |> Scad.translate (v3 0. 0. dome_z)
  and base =
    let slab =
      Scad.cube (v3 outer_w outer_h (base_thickness +. 0.001))
      |> Scad.translate (v3 (outer_w /. -2.) (outer_h /. -2.) (dome_z -. base_thickness))
    in
    Scad.difference slab [ sensor_cutter ~z:dome_z sensor_depth ]
  and pillars =
    let cyl = Scad.linear_extrude ~height:dome_thickness Bottom.ellipse in
    Scad.(
      union
        [ translate (v3 Bottom.ellipse_x 0. 0.) cyl
        ; translate (v3 (Bottom.ellipse_x *. -1.) 0. 0.) cyl
        ]
      |> translate (v3 0. 0. (bottom_z -. dome_thickness)))
  in
  let cutout =
    let internals =
      Scad.union [ Scad.translate (v3 0. 0. bottom_z) bottom_cut; dome_cut ]
    in
    match cap_cutout_height with
    | Some h ->
      Scad.union
        [ Scad.ztrans
            (2.5 +. h +. (thickness /. 2.))
            (Scad.cube ~center:true (v3 20. 20. 7.))
        ; internals
        ]
    | None   -> internals
  and clip hole = Scad.union [ base; hole; pillars ] in
  KeyHole.(
    make
      ?render
      ?cap
      ~cutout
      { spec = Kind.Key
      ; outer_w
      ; outer_h
      ; inner_w
      ; inner_h
      ; thickness
      ; clip
      ; cap_height
      ; clearance
      })

let make_hole
    ?render
    ?cap
    ?outer_w
    ?outer_h
    ?inner_w
    ?inner_h
    ?thickness
    ?cap_height
    ?cap_cutout_height
    ?clearance
    ?dome_w
    ?dome_waist_clip
    ?dome_thickness
    ?base_thickness
    ?sensor_depth
    ?sensor_cutter
    ()
  =
  hole_of_config
    ?render
    ?cap
    (Config.make
       ?outer_w
       ?outer_h
       ?inner_w
       ?inner_h
       ?thickness
       ?cap_height
       ?cap_cutout_height
       ?clearance
       ?dome_w
       ?dome_waist_clip
       ?dome_thickness
       ?base_thickness
       ?sensor_depth
       ?sensor_cutter
       () )

let empty_hole_of_config
    ?render
    ?cap
    Config.
      { outer_w
      ; outer_h
      ; inner_w
      ; inner_h
      ; thickness
      ; cap_height
      ; cap_cutout_height
      ; clearance
      ; _
      }
  =
  Mx.make_hole
    ?render
    ?cap
    ~outer_w
    ~outer_h
    ~inner_w
    ~inner_h
    ~thickness
    ~cap_height
    ~cap_cutout_height
    ~clearance
    ()

let make_empty_hole
    ?render
    ?cap
    ?outer_w
    ?outer_h
    ?inner_w
    ?inner_h
    ?thickness
    ?cap_height
    ?cap_cutout_height
    ?clearance
    ()
  =
  empty_hole_of_config
    ?render
    ?cap
    (Config.make
       ?outer_w
       ?outer_h
       ?inner_w
       ?inner_h
       ?thickness
       ?cap_height
       ?cap_cutout_height
       ?clearance
       () )
