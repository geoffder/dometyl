open Base
open Scad_ml
open Infix

(* TODO:

   What is needed?
   - Key must carry the full path of its front and back ends, along with a
    Points holding coordinates of not the corners as they are originally, but
    instead, the points of the long edges (first point of the corner, e.g.
    beginning of the arc or start of the chamfer), such that connections can be drawn
    disregarding the roundovers
   - These points can then be used with the same transforms that draw the wall
    to create edge paths that can be skinned together to join walls, or be the
    target endpoints for (bespoke of_rows usage likely) sweeps between the
    bases of column walls.
   - Of course, these edge paths will need to take into account the skinning
    that happens at the base of the walls (unimplemented fix that ensures that
    the wall foot is flat on the xy plane). *)
module Steps = struct
  type t =
    [ `PerZ of float
    | `Flat of int
    ]

  let to_int t z =
    match t with
    | `PerZ mm -> Int.max 2 (Float.to_int (z /. mm))
    | `Flat n  -> n
end

module Edge = struct
  include Bezier3

  let point_at_z ?(max_iter = 100) ?(tolerance = 0.001) t z =
    let bez_frac =
      Util.bisection_exn ~max_iter ~tolerance ~f:(fun s -> V3.get_z (t s) -. z) 0. 1.
    in
    t bez_frac
end

module EdgeDrawer = struct
  type drawer = V3.t -> Edge.t

  type t =
    { top : drawer
    ; bot : drawer
    }

  let make
      ?(max_iter = 100)
      ?(tolerance = 0.001)
      ~(get_bez : bool -> V3.t -> Edge.t)
      Points.{ top_left; top_right; bot_left; bot_right; _ }
    =
    let find_between lp rp { x; y; z = _ } =
      let ({ x = dx; y = dy; z = _ } as diff) = V3.sub rp lp in
      let get_major, target =
        if Float.(abs dx > abs dy) then V3.get_x, x else V3.get_y, y
      in
      let ml = get_major lp
      and mr = get_major rp in
      if Float.(target > ml && target < mr) || Float.(target < ml && target > mr)
      then (
        let get s = V3.(lp +@ (diff *$ s)) in
        let pos =
          Util.bisection_exn
            ~max_iter
            ~tolerance
            ~f:(fun s -> get_major (get s) -. target)
            0.
            1.
        in
        get pos )
      else if Float.(abs (target -. ml) < abs (target -. mr))
      then lp
      else rp
    in
    { top = find_between top_left top_right >> get_bez true
    ; bot = find_between bot_left bot_right >> get_bez false
    }

  let map ~f t = { top = f t.top; bot = f t.bot }
  let translate p = map ~f:(fun d start -> d start >> V3.add p)
  let xtrans x = map ~f:(fun d start -> d start >> V3.xtrans x)
  let ytrans y = map ~f:(fun d start -> d start >> V3.ytrans y)
  let ztrans z = map ~f:(fun d start -> d start >> V3.ztrans z)
  let scale s = map ~f:(fun d start -> d start >> V3.scale s)
  let mirror ax = map ~f:(fun d start -> d start >> V3.mirror ax)
  let rotate ?about r = map ~f:(fun d start -> d start >> V3.rotate ?about r)
  let xrot ?about r = map ~f:(fun d start -> d start >> V3.xrot ?about r)
  let yrot ?about r = map ~f:(fun d start -> d start >> V3.yrot ?about r)
  let zrot ?about r = map ~f:(fun d start -> d start >> V3.zrot ?about r)

  let axis_rotate ?about ax r =
    map ~f:(fun d start -> d start >> V3.axis_rotate ?about ax r)

  let quaternion ?about q = map ~f:(fun d start -> d start >> V3.quaternion ?about q)
  let affine m = map ~f:(fun d start -> d start >> V3.affine m)
end

module Edges = struct
  type t =
    { top_left : Edge.t [@scad.d3]
    ; top_right : Edge.t
    ; bot_left : Edge.t
    ; bot_right : Edge.t
    }
  [@@deriving scad]

  let map ~f t =
    { top_left = f t.top_left
    ; top_right = f t.top_right
    ; bot_left = f t.bot_left
    ; bot_right = f t.bot_right
    }

  let of_cw_path_exn = function
    | [ top_left; top_right; bot_right; bot_left ] ->
      { top_left; top_right; bot_left; bot_right }
    | _ -> failwith "Expect list of length 4, with edges beziers in clockwise order."

  let of_cw_path l =
    try Ok (of_cw_path_exn l) with
    | Failure e -> Error e

  let get t = function
    | `TL -> t.top_left
    | `TR -> t.top_right
    | `BL -> t.bot_left
    | `BR -> t.bot_right
end

type config =
  { d1 : float
  ; d2 : float
  ; z_off : float
  ; thickness : float
  ; clearance : float
  ; n_steps : Steps.t
  ; n_facets : int
  ; eyelet_config : Eyelet.config option
  }

let default =
  { d1 = 2.
  ; d2 = 5.
  ; z_off = 0.
  ; thickness = 3.5
  ; clearance = 1.5
  ; n_steps = `Flat 4
  ; n_facets = 1
  ; eyelet_config = None
  }

type t =
  { scad : Scad.d3
  ; start : Points.t
  ; foot : Points.t
  ; edge_drawer : EdgeDrawer.t
  ; edges : Edges.t
  ; screw : Eyelet.t option
  }
[@@deriving scad]

(* Compute a rotation around the face's bottom or top edge, depending on which way
   it's orthoganal is pointing in z, that makes the short edge (between the
   bottom and top long edge), as vertical as possible. The pivoted face, and its
   new orthogonal are returned. *)
let swing_face key_origin face =
  let dir = Key.Face.direction face in
  let ortho = V3.(normalize (face.points.centre -@ key_origin)) in
  let about, z_sign =
    if Float.(V3.get_z ortho > 0.)
    then V3.mid face.points.bot_left face.points.bot_right, 1.
    else V3.mid face.points.top_left face.points.top_right, -1.
  in
  let q =
    let proj = Plane.(project @@ of_normal dir) in
    let up = V3.(normalize (face.points.top_left -@ face.points.bot_left)) in
    Quaternion.make dir @@ (V2.angle (proj up) (proj @@ v3 0. 0. 1.) *. z_sign)
  in
  Key.Face.quaternion ~about q face, V3.quaternion q ortho

(* TODO: Think of scaling d1 based on how high the key is, though maybe should
 * do so in the higher level functions in walls that call this one. Having a larger
 * d1 value will improve the clearance for the tall columns, which aren't in such a
 * hurry to move in xy (since they have a larger distance to do it).
 *
 * NOTE: `Flat and `ZRatio as the type for d1? `ZRatio being a % of Z that should
 * be assigned as d1. Would that make the bow of the curve more consistent without
 * implementing and switching to splines?
   Update: Clearance not using d1 has been added, so this is more of a cosmetic
   consideration now. *)

let poly_siding
    ?(x_off = 0.)
    ?(y_off = 0.)
    ?(z_off = 0.)
    ?(clearance = 1.5)
    ?(n_steps = `Flat 4)
    ?(n_facets = 1)
    ?(d1 = 2.)
    ?(d2 = 5.)
    ?thickness
    ?eyelet_config
    side
    (key : Key.t)
  =
  let start_face = Key.Faces.face key.faces side
  and thickness = Option.value ~default:key.config.thickness thickness in
  let pivoted_face, ortho = swing_face key.origin start_face in
  let cleared_face = Key.Face.translate (V3.map (( *. ) clearance) ortho) pivoted_face in
  let xy = V3.(normalize (mul ortho (v3 1. 1. 0.)))
  (* NOTE: I think z_hop is much less relevant now, check what kind of values it
   * is getting, and consider removing. *)
  and z_hop = (Float.max 0. (V3.get_z ortho) *. key.config.thickness) +. z_off
  and top_offset =
    V3.(
      mul (v3 1. 1. 0.) (cleared_face.points.bot_right -@ cleared_face.points.top_right))
  in
  let get_bez top ({ x; y; z } as start) =
    let jog, d1, plus =
      let half_delta = (d2 -. d1) /. 2. in
      if top
      then thickness, d1 +. Float.max half_delta 0., top_offset
      else 0., d1 +. Float.min half_delta 0., v3 0. 0. 0.
    in
    let p1 = V3.(start -@ (ortho *$ 0.01)) (* fudge for union *)
    and p2 =
      V3.(
        mul xy (v3 (d1 +. jog) (d1 +. jog) 0.)
        |> add (v3 (x +. x_off) (y +. y_off) (z +. z_hop))
        |> add plus)
    and p3 =
      V3.(
        add (mul xy (v3 (d2 +. jog) (d2 +. jog) 0.)) (v3 (x +. x_off) (y +. y_off) 0.)
        |> add plus)
    in
    p3, Bezier3.make [ p1; p2; p3 ]
  in
  let cw_points =
    let n = n_facets - 1 in
    Util.fill_points
      ~init:
        (Util.fill_points ~n cleared_face.points.bot_left cleared_face.points.bot_right)
      ~n
      cleared_face.points.top_right
      cleared_face.points.top_left
  in
  let corners =
    (* drop the extra non-corner elements for intermediate facets *)
    List.filteri ~f:(fun i _ ->
        i = 0 || i = n_facets || i = n_facets + 1 || i = 3 + ((n_facets - 1) * 2) )
  and steps =
    let adjust V3.{ z; _ } =
      let lowest_z =
        let f m p = Float.min m p.z in
        Points.fold ~f ~init:Float.max_value cleared_face.points
      in
      Float.(to_int ((1. +. ((z -. lowest_z) /. z)) *. of_int (Steps.to_int n_steps z)))
    in
    `Ragged (List.map ~f:adjust cw_points)
  and end_ps, bezs =
    List.foldi
      ~f:(fun i (ends, bs) p ->
        let e, b = get_bez (i > n_facets) p in
        e :: ends, b :: bs )
      ~init:([], [])
      (List.rev cw_points)
  in
  let foot = Points.of_cw_path_exn (corners end_ps) in
  let screw =
    let f config =
      let open Eyelet in
      let placement =
        let n = V3.negate xy in
        match config with
        | { hole = Through; _ } -> Normal (V2.of_v3 n)
        | { hole = Inset _; outer_rad; _ } ->
          let offset = outer_rad +. V3.(norm (sub foot.top_left foot.bot_left) /. 4.) in
          Point V3.(to_v2 (mid foot.top_left foot.top_right +@ (n *$ offset)))
      in
      make ~placement config (V2.of_v3 foot.bot_left) (V2.of_v3 foot.bot_right)
    in
    Option.map ~f eyelet_config
  in
  (* TODO: add a rel factor of the key thickness, or absolute z as the bezier
    stopping point (where the linear transition to the flat foot begins). Also,
    maybe an `Auto option, which initially makes a bez down to 0, checks how
    much the lowest point over shot, then calculate the final bez with that
     correction (plus a small fudge to ensure no failure).

     - bez generated by a function that takes end_z
     - calculate transforms for it, and apply the last one to the shape
     - determine how sunken it is below the xy plane
     - generate new bez (and transforms) with the new end_z *)
  let end_z = key.config.thickness /. 4. in
  let bz =
    let d1 = d1 *. 7. in
    let d2 = d2 *. 2. in
    let x_off = 0. in
    let y_off = 0. in
    let ({ x; y; z } as cx) = cleared_face.points.centre in
    let p1 = V3.(cx -@ (ortho *$ 0.01)) (* fudge for union *)
    and p2 = V3.((xy *@ v3 d1 d1 0.) +@ v3 (x +. x_off) (y +. y_off) (z +. z_hop))
    and p3 = V3.((xy *@ v3 d2 d2 0.) +@ v3 (x +. x_off) (y +. y_off) end_z) in
    Bezier3.make [ p1; p2; p3 ]
  in
  let fn = 6 in
  let bz_pts = Bezier3.curve ~fn bz in
  let dir = Points.direction cleared_face.points in
  let transforms = Path3.to_transforms ~mode:`NoAlign bz_pts in
  (* Stdio.printf "xoff = %f; yoff = %f\n" x_off y_off; *)
  let _mesh =
    let pth = cleared_face.path in
    let centred = Path3.translate (V3.negate @@ cleared_face.points.centre) pth in
    let transforms =
      (* counter the rotation created by the z tilt of the face, such that the
           angle of the wall is more in line with the xy angle of the originating face *)
      let a = V3.angle dir (v3 dir.x dir.y 0.) *. Math.sign dir.z *. -1. in
      let s = Quaternion.(slerp (make ortho 0.) (make ortho a)) in
      let step = 1. /. Float.of_int fn
      and ez = Easing.make (v2 0.42 0.) (v2 1. 1.) in
      let f i m = Affine3.((of_quaternion @@ s (ez (Float.of_int i *. step))) %> m) in
      List.mapi ~f transforms
    in
    (* TODO: should expose the function of this, since I would like to use it
   for `Auto end_z calculation (just need the last scaled shape). Then after
   end_z is known, regen the bez, transforms, then use scaled with mapi over
   transforms instead of map2. Also, should work with x and y of course, rather
    than just x as this demo does. *)
    let scaled =
      let p = Path3.to_plane centred in
      let a = V2.angle (V3.project p dir) (v2 1. 0.) in
      let aligned = Path2.rotate a @@ Path3.project p centred in
      let frac = 0.2 in
      let step = 1. /. Float.of_int fn
      and ez = Easing.make (v2 0.42 0.) (v2 1. 1.) in
      let f i =
        Path2.scale (v2 (1. -. (ez (Float.of_int i *. step) *. frac)) 1.) aligned
        |> Path2.rotate (-.a)
        |> Path2.lift p
      in
      List.init (fn + 1) ~f
    in
    (* let rows = List.map ~f:(fun m -> Path3.affine m centred) transforms in *)
    let rows = List.map2_exn ~f:(fun s m -> Path3.affine m s) scaled transforms in
    let clearing = Mesh.slice_profiles ~slices:(`Flat 5) [ start_face.path; pth ] in
    let final =
      let s = List.last_exn rows in
      (* FIXME: would like to use straight plane projection rather than this rotation
    then scaling style flattening, but with finely curved key paths combined
    with enough tilt, it could result in broken paths (point bunching ->
    reversals) that will break the mesh. I should perhaps run a point
    deduplication with a large epsilon, then use a reindexing skin. *)
      (* let n = Path3.normal s in *)
      (* let c = bz 1. in *)
      (* let flat = *)
      (*   Path3.quaternion ~about:c (Quaternion.align n (v3 0. 0. (-1.))) s *)
      (*   |> Path3.scale (v3 1. 1. 0.) *)
      (* in *)
      let flat = Path3.of_path2 @@ Path3.project Plane.xy s in
      Mesh.slice_profiles ~slices:(`Flat 5) [ s; flat ]
    in
    Mesh.of_rows (List.concat [ clearing; List.tl_exn rows; List.tl_exn final ])
  in
  ignore steps;
  { scad =
      (* Scad.hull [ start_face.scad; cleared_face.scad ] *)
      (* :: Path3.show_points (Fn.const @@ Scad.sphere 1.) bz_pts *)
      (* :: Path3.show_points *)
      (*      (Fn.const @@ Scad.sphere 1.) *)
      (*      Bezier3.(curve ~fn:16 @@ translate cleared_face.points.centre _mbz) *)
      Mesh.to_scad _mesh :: Option.value_map ~default:[] ~f:(fun s -> [ s.scad ]) screw
      |> Scad.union
      |> Fn.flip
           Scad.difference
           (Option.value_map ~default:[] ~f:(fun s -> Option.to_list s.cut) screw)
  ; start = start_face.points
  ; foot
  ; edge_drawer =
      EdgeDrawer.make
        ~get_bez:(fun top start -> snd (get_bez top start))
        cleared_face.points
  ; edges = Edges.of_cw_path_exn (corners bezs)
  ; screw
  }

let poly_of_config
    ?x_off
    ?y_off
    { d1; d2; z_off; thickness; clearance; n_steps; n_facets; eyelet_config }
  =
  poly_siding
    ~d1
    ~d2
    ?x_off
    ?y_off
    ~z_off
    ~thickness
    ~clearance
    ~n_steps
    ~n_facets
    ?eyelet_config

let column_drop
    ?z_off
    ?clearance
    ?n_steps
    ?n_facets
    ?d1
    ?d2
    ?thickness
    ?eyelet_config
    ~spacing
    ~columns
    side
    idx
  =
  let key, face, hanging =
    let c : Column.t = Map.find_exn columns idx in
    match side with
    | `North ->
      let key = snd @@ Map.max_elt_exn c.keys in
      let edge_y = V3.get_y key.faces.north.points.centre in
      key, key.faces.north, Float.(( <= ) edge_y)
    | `South ->
      let key = Map.find_exn c.keys 0 in
      let edge_y = V3.get_y key.faces.south.points.centre in
      key, key.faces.south, Float.(( >= ) edge_y)
  in
  let x_dodge =
    match Map.find columns (idx + 1) with
    | Some next_c ->
      let right_x = V3.get_x face.points.top_right
      and next_face = Key.Faces.face (snd @@ Map.max_elt_exn next_c.keys).faces side in
      let diff =
        if hanging (V3.get_y next_face.points.centre)
        then right_x -. V3.get_x next_face.points.bot_left
        else -.spacing
      in
      if Float.(diff > 0.) then diff +. spacing else Float.max 0. (spacing +. diff)
    | _           -> 0.
  in
  poly_siding
    ~x_off:(x_dodge *. -1.)
    ?z_off
    ?clearance
    ?d1
    ?d2
    ?thickness
    ?n_steps
    ?n_facets
    ?eyelet_config
    side
    key

let drop_of_config
    ~spacing
    { d1; d2; z_off; thickness; clearance; n_steps; n_facets; eyelet_config }
  =
  column_drop
    ~d1
    ~d2
    ~z_off
    ~thickness
    ~clearance
    ~n_steps
    ~n_facets
    ~spacing
    ?eyelet_config

let start_direction { start = { top_left; top_right; _ }; _ } =
  V3.normalize V3.(top_left -@ top_right)

let foot_direction { foot = { top_left; top_right; _ }; _ } =
  V3.normalize V3.(top_left -@ top_right)

let to_scad t = t.scad
