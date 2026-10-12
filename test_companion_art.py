import unittest
import companion_art as C
import mascot as M
import menu_art as U

class CompanionArtTests(unittest.TestCase):
    def test_every_expression_frame_has_complete_palette_and_bounds(self):
        art=C.export(M.SKINS,M.SLOTS,M.EYES,M.FRAMES)
        for fig in C.WALKING_FIGURES:
            for eye in M.EYES:
                for frame in range(C.WALK_FRAMES):
                    used=set(''.join(art['walking_sprites'][f'{fig}/{eye}/{frame}']))-{'.'}
                    for skin in M.SKINS: self.assertTrue(used<=art['palettes'][f'{fig}/{skin}'].keys(),fig)
        for fig in C.FIGURES:
            for eye in M.EYES:
                for f in range(M.FRAMES):
                    rows=art['sprites'][f'{fig}/{eye}/{f}']
                    self.assertEqual(len(rows),32)
                    self.assertTrue(all(len(r)==32 for r in rows))
                    used=set(''.join(rows))-{'.'}
                    for skin in M.SKINS:
                        palette=art['palettes'][f'{fig}/{skin}']
                        self.assertTrue(used<=palette.keys())
                        self.assertTrue(all(len(v)==7 and v.startswith('#') for v in palette.values()))
    def test_gestures_move_parts_while_feet_stay_grounded(self):
        for fig in C.FIGURES:
            frames=[C.sprite(fig,'open',f) for f in range(8)]
            self.assertGreaterEqual(len({tuple(r) for r in frames}),3,fig)
            if fig != 'rooster': self.assertTrue(all(r[-4:]==frames[0][-4:] for r in frames),fig)
            else:
                self.assertGreater(len({tuple(r[-7:]) for r in frames}),1)
                self.assertTrue(all(any(c!='.' for c in r[-1]) for r in frames))
            self.assertTrue(any(c!='.' for c in frames[0][-1]),fig)
    def test_alarm_and_nudge_are_distinct_in_every_frame(self):
        for fig in C.FIGURES:
            for f in range(8):
                self.assertNotEqual(C.sprite(fig,'wide',f),C.sprite(fig,'glance',f),fig)
    def test_detail_is_original_art_not_an_enlarged_small_sprite(self):
        art={tuple(C.sprite(fig,'open',0)) for fig in C.FIGURES}
        self.assertEqual(len(art),len(C.FIGURES))
        for fig in C.FIGURES:
            rows=C.sprite(fig,'open',0)
            self.assertGreaterEqual(len(set(''.join(rows))-{'.'}),5,fig)
            self.assertNotEqual(rows[:23],M.sprite(0,'open',0,M.FIGURES[fig]))
    def test_walk_gaits_have_eight_distinct_bounded_frames(self):
        art=C.export(M.SKINS,M.SLOTS,M.EYES,M.FRAMES)
        for fig in C.WALKING_FIGURES:
            frames=[art['walking_sprites'][f'{fig}/open/{f}'] for f in range(C.WALK_FRAMES)]
            self.assertGreaterEqual(len({tuple(rows) for rows in frames}), 4, fig)
            for rows in frames:
                height,width=(23,22) if fig in ('cat','crab') else (32,32)
                self.assertEqual(len(rows), height, fig)
                self.assertTrue(all(len(row)==width for row in rows), fig)

    def test_machine_steps_lift_one_foot_while_the_other_is_grounded(self):
        for fig in ('robot','antenna'):
            frames=[C.walking_sprite(fig,'open',f) for f in range(C.WALK_FRAMES)]
            self.assertGreaterEqual(len({tuple(rows[27:]) for rows in frames}),6,fig)
            for rows in frames:
                self.assertTrue(any(ch!='.' for ch in rows[31]),fig)
            planted=lambda rows: [x for x,ch in enumerate(rows[31]) if ch!='.']
            self.assertNotEqual(planted(frames[2]),planted(frames[6]),fig)

    def test_walking_profiles_are_distinct_from_portraits_and_expressions_survive(self):
        for fig in C.WALKING_FIGURES:
            for frame in range(C.WALK_FRAMES):
                if fig!='palm' and fig in C.FIGURES:
                    self.assertNotEqual(C.walking_sprite(fig,'open',frame),C.sprite(fig,'open',frame),fig)
                if fig!='palm':
                    self.assertNotEqual(C.walking_sprite(fig,'wide',frame),C.walking_sprite(fig,'glance',frame),fig)
                    self.assertNotEqual(C.walking_sprite(fig,'open',frame),C.walking_sprite(fig,'shut',frame),fig)

    def test_planted_foot_stays_fixed_in_screen_space(self):
        for scale in (2,3):
            screen_positions=[]
            for frame in range(8):
                toe,floor=C.foot_pose(14,frame)
                screen_positions.append(frame*scale+toe*scale)
                self.assertEqual(floor,31)
            self.assertEqual(len(set(screen_positions)),1)

    def test_recovering_foot_lifts_and_passes_ahead_of_support(self):
        for near_hip,far_hip in ((21,20),(20,19),(14,13)):
            crossings=[]
            for phase in range(8,16):
                swing_x,swing_y=C.foot_pose(far_hip,phase)
                support_x,support_y=C.foot_pose(near_hip,(phase+8)%16)
                self.assertLess(swing_y,support_y)
                crossings.append(swing_x>support_x)
                c=C.Canvas()
                C._side_leg(c,far_hip,25,phase)
                self.assertTrue(any(ch!='.' for ch in c.rows()[swing_y]))
                self.assertTrue(all(ch=='.' for ch in c.rows()[31]))
            self.assertTrue(any(crossings))

    def test_walkers_keep_a_foot_or_body_on_the_floor(self):
        for fig in ('rabbit', 'pup', 'rex', 'snowman', 'robot', 'antenna', 'orb'):
            for frame in range(C.WALK_FRAMES):
                rows = C.walking_sprite(fig, 'open', frame)
                self.assertTrue(any(ch != '.' for ch in rows[-1]), '%s frame %d' % (fig, frame))

    def test_original_profiles_keep_portrait_dimensions(self):
        for fig in ('cat','crab'):
            for frame in range(C.WALK_FRAMES):
                rows=C.walking_sprite(fig,'open',frame)
                self.assertEqual((len(rows[0]),len(rows)),(M.W,M.H))


class MenuArtTests(unittest.TestCase):
    def test_small_icons_are_complete_and_expressions_remain_distinct(self):
        art=U.export(M.SKINS,M.FRAMES)
        for fig in U.FIGURES:
            variants=[]
            for eyes in M.EYES:
                rows=U.sprite(fig,eyes,0);variants.append(tuple(rows))
                self.assertEqual(len(rows),22)
                self.assertTrue(all(len(r)==22 for r in rows))
                used=set(''.join(rows))-{'.'}
                for skin in M.SKINS:self.assertTrue(used <= art['palettes'][f'{fig}/{skin}'].keys())
            self.assertEqual(len(set(variants)),5,fig)
        self.assertEqual(len({tuple(U.sprite(f,'open',0)) for f in U.FIGURES}),len(U.FIGURES))

    def test_original_mascots_also_have_a_distinct_grounded_walking_gait(self):
        art=M.export()
        for fig in (M.CAT, M.CRAB):
            frames=[art['walk_sprites'][f'{fig.id}/0/open/{f}'] for f in range(8)]
            self.assertGreaterEqual(len({tuple(r) for r in frames}),4,fig.name)
            self.assertTrue(all(len(rows)==23 and all(len(row)==22 for row in rows)
                                for rows in frames),fig.name)

if __name__=='__main__': unittest.main()
