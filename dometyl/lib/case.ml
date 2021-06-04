open! Base
open! Scad_ml
open! Infix
open! Sigs
module Key = KeyHole.Make (Niz.HoleConfig)

module Col = Column.Make (struct
  (* TODO: Update how modules / code is organized to make per column curavature
   * settings a non-painful addition. *)
  let n_keys = 3

  module Key = Key

  module Curve = Curvature.Make (struct
    let centre_idx = 1
    let well = Some Curvature.{ angle = Math.pi /. 12.; radius = 85. }
    let fan = None
  end)
end)

module Thumb = struct
  include Column.Make (struct
    let n_keys = 3

    module Key = KeyHole.RotateClips (Key)

    module Curve = Curvature.Make (struct
      let centre_idx = 1
      let well = Some Curvature.{ angle = Math.pi /. 12.; radius = 85. }
      let fan = Some Curvature.{ angle = Math.pi /. 12.; radius = 85. }
    end)
  end)

  (* orient along x-axis *)
  let t = rotate (0., 0., Math.pi /. -2.) t
end

module Plate = struct
  type t =
    { scad : Model.t
    ; columns : Col.t Map.M(Int).t
    ; thumb : Thumb.t
    }

  let n_cols = 5
  let spacing = 2.
  let centre_col = 2
  let tent = Math.pi /. 6.
  let thumb_offset = 7., -50., -3.
  let thumb_angle = Math.(0., pi /. -4., pi /. 5.)
  let clearance = 7.

  (* TODO: tune *)
  let lookup = function
    | 2 -> 0., 6., -6. (* middle *)
    | 3 -> 0., 3., -2. (* ring *)
    | i when i >= 4 -> 0., -12., 6. (* pinky *)
    | _ -> 0., 0., 0.

  let col_offsets =
    let space = Col.Key.outer_w +. spacing in
    let f m i =
      let data = Util.(lookup i <+> (space *. Float.of_int i, 0., 0.)) in
      Map.add_exn ~key:i ~data m
    in
    List.fold ~f ~init:(Map.empty (module Int)) (List.range 0 n_cols)

  let centre_offset = Map.find_exn col_offsets centre_col

  let apply_tent (type a) (module M : Transformable with type t = a) off col : a =
    M.(rotate_about_pt (0., tent, 0.) Util.(off <-> centre_offset) col)

  let place_col off = apply_tent (module Col) off Col.t |> Col.translate off

  let columns, thumb =
    let placed_cols = Map.map ~f:place_col col_offsets in
    let lift =
      let lowest_z =
        let face_low ({ points = ps; _ } : KeyHole.Face.t) =
          KeyHole.Face.Points.fold
            ~f:(fun m p -> Float.min m (Util.get_z p))
            ~init:Float.max_value
            ps
        in
        let key_low ({ faces = fs; _ } : Key.t) =
          KeyHole.Faces.fold
            ~f:(fun m face -> Float.min m (face_low face))
            ~init:Float.max_value
            fs
        in
        let col_low ({ keys = ks; _ } : Col.t) =
          Map.fold
            ~f:(fun ~key:_ ~data m -> Float.min m (key_low data))
            ~init:Float.max_value
            ks
        in
        Map.fold
          ~f:(fun ~key:_ ~data m -> Float.min m (col_low data))
          ~init:Float.max_value
          placed_cols
      in
      clearance -. lowest_z
    in
    let thumb =
      let open Thumb in
      let placed = rotate thumb_angle t |> translate thumb_offset in
      apply_tent (module Thumb) (Map.find_exn placed.keys 1).origin placed
      |> translate (0., 0., lift)
    in
    Map.map ~f:(Col.translate (0., 0., lift)) placed_cols, thumb

  let scad =
    Model.union
      (Map.fold ~f:(fun ~key:_ ~data l -> data.scad :: l) ~init:[ thumb.scad ] columns)

  let bez_wall side i =
    let key, face, y_sign =
      let c = Map.find_exn columns i in
      match side with
      | `North ->
        let key = snd @@ Map.max_elt_exn c.keys in
        key, key.faces.north, 1.
      | `South ->
        let key = Map.find_exn c.keys 0 in
        key, key.faces.south, -1.
    in
    let x_tent = KeyHole.x_angle key
    and KeyHole.Face.{ points = { centre = (_, _, cz) as centre; _ }; _ } = face in
    let jog_y = Float.cos x_tent *. (Key.thickness *. 1.5)
    and jog_x =
      let edge_y = Util.get_y face.points.centre in
      match Map.find columns (i + 1) with
      | Some next_c ->
        let right_x = Util.get_x face.points.top_right
        and next_key = snd @@ Map.max_elt_exn next_c.keys in
        let diff =
          match side with
          | `North when Float.(Util.get_y next_key.faces.north.points.centre >= edge_y) ->
            right_x -. Util.get_x next_key.faces.north.points.bot_left
          | `South when Float.(Util.get_y next_key.faces.south.points.centre <= edge_y) ->
            right_x -. Util.get_x next_key.faces.south.points.bot_left
          | _ -> -.spacing
        in
        if Float.(diff > 0.) then diff +. spacing else Float.max 0. (spacing +. diff)
      | _           -> 0.
    and start =
      (* move out of the key wall, parallel to the keys columnar tilt *)
      Util.(
        centre
        <+> ( 0.
            , ((Float.cos x_tent *. Key.thickness /. 2.) -. 0.001) *. y_sign
            , Float.sin x_tent *. Key.thickness /. 2. *. y_sign ))
    and chunk =
      Model.cylinder ~center:true (Key.thickness /. 2.) Key.outer_w
      |> Model.rotate (0., (Math.pi /. 2.) +. tent, 0.)
    in
    let wall =
      Bezier.quad_hull
        ~t1:(0., 0., 0.)
        ~t2:(-.jog_x, y_sign *. (3. +. jog_y), Float.sin x_tent *. (Key.thickness +. 2.))
        ~t3:(-.jog_x, y_sign *. (5. +. jog_y), -.cz +. (Key.thickness /. 2.))
        ~r1:(0., 0., 0.)
        ~r2:(0., -.tent, 0.)
        ~r3:(0., -.tent, 0.)
        ~step:0.1
        chunk
    in
    Model.union
      [ Model.hull [ Model.translate start chunk; face.scad ]
      ; wall |> Model.translate start
      ]

  let scad =
    Model.union
      [ scad
      ; bez_wall `South 2
      ; bez_wall `South 3
      ; bez_wall `South 4
      ; bez_wall `North 0
      ; bez_wall `North 1
      ; bez_wall `North 2
      ; bez_wall `North 3
      ; bez_wall `North 4
      ]

  let t = { scad; columns; thumb }
end

module A3144Cutout = Sensor.Make (Sensor.A3144PrintConfig)

module NizPlatform = Niz.Platform.Make (struct
  module HoleConfig = Niz.HoleConfig
  module SensorCutout = A3144Cutout

  let w = 20.
  let dome_w = 19.
  let dome_waist = 15. (* width at narrow point, ensure enough space at centre *)

  (* NOTE: BKE ~= 0.95mm; DES ~= 0.73mm. A value of 1.15 seems to fit both without
   * being too tight or loose on either. *)
  let dome_thickness = 1.15
  let base_thickness = 2.25
  let sensor_depth = 1.5
  let snap_clearance = 0.3
  let snap_len = 0.7
  let lug_height = 1.5
end)

let niz_cross_section =
  Model.difference
    (Model.union
       [ Model.translate
           (0., 0., NizPlatform.wall_height +. (Key.thickness /. 2.))
           Key.t.scad
       ; NizPlatform.scad
       ] )
    [ Model.cube ~center:true (25., 15., 20.) |> Model.translate (0., -7.5, 0.) ]
