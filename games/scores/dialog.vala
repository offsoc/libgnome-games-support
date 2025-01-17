/* -*- Mode: vala; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-
 *
 * Copyright © 2014 Nikhar Agrawal
 *
 * This file is part of libgnome-games-support.
 *
 * libgnome-games-support is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * libgnome-games-support is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with libgnome-games-support.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Games {
namespace Scores {

private class Dialog : Gtk.Dialog
{
    private Context context;
    private Category? active_category = null;
    private int rows_to_display = 10;

    private Gtk.ComboBoxText? combo = null;
    private Gtk.Label? category_label = null;
    private Gtk.HeaderBar? headerbar = null;
    private Gtk.Grid grid;

    private Style scores_style;
    private Score? new_high_score;
    private Category? scores_active_category;

    public Dialog (Context context, string category_type, Style style, Score? new_high_score, Category? current_cat, Gtk.Window window, string icon_name)
    {
        Object (use_header_bar : 1);

        resizable = false;

        this.context = context;
        this.transient_for = window;
        this.new_high_score = new_high_score;

        scores_style = style;
        scores_active_category = current_cat;

        headerbar = (Gtk.HeaderBar) this.get_header_bar ();

        headerbar.show_title_buttons = (new_high_score == null);

        if (new_high_score != null)
        /* Appears at the top of the dialog, as the heading of the dialog */
            this.title = _("Congratulations!");
        else if (scores_style == Style.POINTS_GREATER_IS_BETTER || scores_style == Style.POINTS_LESS_IS_BETTER)
            this.title = _("High Scores");
        else
            this.title = _("Best Times");

        var vbox = this.get_content_area ();
        vbox.orientation = Gtk.Orientation.VERTICAL;

        if (!context.has_scores () && new_high_score == null)
        {
            vbox.spacing = 4;
            vbox.hexpand = true;
            vbox.vexpand = true;
            vbox.valign = Gtk.Align.CENTER;
            vbox.get_style_context ().add_class ("dim-label");

            var image = new Gtk.Image ();
            image.icon_name = icon_name + "-symbolic";
            image.pixel_size = 64;
            image.opacity = 0.2;
            vbox.append (image);

            var title_label = new Gtk.Label ("<b><span size=\"large\">" + _("No scores yet") + "</span></b>");
            title_label.use_markup = true;
            vbox.append (title_label);

            var description_label = new Gtk.Label (_("Play some games and your scores will show up here."));
            vbox.append (description_label);

            width_request = 450;
            height_request = 500;

            return;
        }

        vbox.spacing = 20;

        var catbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        catbar.margin_top = 20;
        catbar.margin_start = 20;
        catbar.margin_end = 20;
        catbar.halign = Gtk.Align.CENTER;

        vbox.append (catbar);

        var hdiv = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        vbox.append (hdiv);

        var label = new Gtk.Label (category_type);
        label.use_markup = true;
        label.halign = Gtk.Align.CENTER;
        catbar.append (label);

        var categories = context.get_categories ();
        if (new_high_score != null || categories.length () == 1)
        {
            if (new_high_score == null)
                scores_active_category = ((!) categories.first ()).data;
            category_label = new Gtk.Label (scores_active_category.name);
            category_label.use_markup = true;
            category_label.halign = Gtk.Align.CENTER;
            category_label.valign = Gtk.Align.CENTER;
            catbar.append (category_label);
        }
        else
        {
            combo = new Gtk.ComboBoxText ();
            combo.focus_on_click = false;
            catbar.append (combo);
            combo.changed.connect (load_scores);
        }

        grid = new Gtk.Grid ();
        vbox.append (grid);

        grid.row_homogeneous = true;
        grid.column_spacing = 40;
        grid.margin_start   = 30;
        grid.margin_end     = 30;
        grid.margin_bottom  = 20;
        grid.halign = Gtk.Align.CENTER;

        /* A column heading in the scores dialog */
        string string_rank = _("Rank");
        var label_column_1 = new Gtk.Label ("<span weight='bold'>" + string_rank + "</span>");
        label_column_1.use_markup = true;
        grid.attach (label_column_1, 0, 0, 1, 1);

        string score_or_time = "";

        if (scores_style == Style.POINTS_GREATER_IS_BETTER || scores_style == Style.POINTS_LESS_IS_BETTER)
            /* A column heading in the scores dialog */
            score_or_time = _("Score");
        else
            score_or_time = _("Time");

        var label_column_2 = new Gtk.Label ("<span weight='bold'>" + score_or_time + "</span>");
        label_column_2.use_markup = true;
        grid.attach (label_column_2, 1, 0, 1, 1);

        /* A column heading in the scores dialog */
        string string_player = _("Player");
        var label_column_3 = new Gtk.Label ("<span weight='bold'>" + string_player + "</span>");
        label_column_3.use_markup = true;
        grid.attach (label_column_3, 2, 0, 1, 1);

        grid.baseline_row = 0;
        fill_grid_with_labels ();

        if (new_high_score != null)
            /* Appears on the top right corner of the dialog. Clicking the button closes the dialog. */
            add_button (_("_Done"), Gtk.ResponseType.OK).get_style_context ().add_class ("suggested-action");

        load_categories ();
    }

    private void fill_grid_with_labels ()
    {
        for (int row = 1; row <= rows_to_display; row++)
        {
            for (int column = 0; column <= 1; column++)
            {
                var label = new Gtk.Label ("");
                label.visible = true;
                label.halign = Gtk.Align.CENTER;
                label.valign = Gtk.Align.CENTER;

                grid.attach (label, column, row, 1, 1);
            }

            var stack = new Gtk.Stack ();
            stack.visible = true;
            stack.hhomogeneous = false;
            stack.vhomogeneous = true;
            stack.transition_type = Gtk.StackTransitionType.NONE;

            var label = new Gtk.Label ("");
            label.visible = true;
            label.justify = Gtk.Justification.CENTER;
            label.valign = Gtk.Align.CENTER;
            stack.add_named (label, "label");

            var entry = new Gtk.Entry ();
            entry.visible = true;
            entry.set_size_request (20, 20);
            entry.hexpand = false;
            entry.vexpand = false;
            stack.add_named (entry, "entry");

            stack.visible_child_name = "label";
            grid.attach (stack, 2, row, 1, 1);
        }
    }

    /* load names and keys of all categories in ComboBoxText */
    private void load_categories ()
    {
        /* If we are adding a high score, we don't wish to load all categories. We only wish to load scores of active category. */
        if (new_high_score != null || combo == null)
        {
            load_scores ();
        }

        if (combo == null)
            return;

        var categories = context.get_categories ();
        categories.foreach ((x) => combo.append (x.key, x.name));

        if (scores_active_category == null)
            combo.active_id = categories.nth_data (0).key;
        else
            combo.active_id = scores_active_category.key;

        if (active_category == null)
        {
            active_category = new Category (categories.nth_data (0).key, categories.nth_data (0).name);
        }
        else
        {
            active_category.key = categories.nth_data (0).key;
            active_category.name = categories.nth_data (0).name;
        }
    }

    /* loads the scores of current active_category */
    private void load_scores ()
    {
        if (new_high_score != null || combo == null)
            active_category = new Category (scores_active_category.key, scores_active_category.name);
        else
            active_category = new Category (combo.get_active_id (), combo.get_active_text ());

        var best_n_scores = context.get_high_scores (active_category, rows_to_display);

        int row_count = 1;

        foreach (var score in best_n_scores)
        {
            display_single_score (score, row_count, best_n_scores.size);
            row_count++;
        }

        if (row_count < rows_to_display + 1)
            make_remaining_labels_empty (row_count);
    }

    /* Use Stack to switch between Entry and Label. All data displayed as labels except when a new high score is being added.
       In which case, Label needs to be replaced by Entry allowing for player to enter name. */
    private void display_single_score (Score score, int row_count, uint no_scores)
    {
        var rank_label = (Gtk.Label) grid.get_child_at (0, row_count);
        rank_label.set_text (row_count.to_string ());

        var score_label = (Gtk.Label) grid.get_child_at (1, row_count);
        if (scores_style == Style.POINTS_GREATER_IS_BETTER || scores_style == Style.POINTS_LESS_IS_BETTER)
        {
            score_label.set_text (score.score.to_string ());
        }
        else
        {
            var minutes = score.score / 60;
            var seconds = score.score % 60;
            score_label.set_text ("%s %s".printf (
                /* Time which may be displayed on a scores dialog. */
                ngettext ("%ld minute", "%ld minutes", minutes).printf (minutes),
                /* Time which may be displayed on a scores dialog. */
                ngettext ("%ld second", "%ld seconds", seconds).printf (seconds)));
        }

        if (new_high_score != null && Score.equals (score, new_high_score))
        {
            /*if (no_scores > 1 && row_count == 1)
                headerbar.subtitle = _("Your score is the best!");
            else
                headerbar.subtitle = _("Your score has made the top ten.");
            */
            var temp_stack = (Gtk.Stack) grid.get_child_at (2, row_count);
            temp_stack.visible_child_name = "entry";

            var entry = (Gtk.Entry) temp_stack.get_visible_child ();
            entry.text = score.user;
            entry.notify["text"].connect (() => {
                context.update_score_name (score, active_category, entry.get_text ());
                score.user = entry.get_text ();
            });
        }

        var name_stack = (Gtk.Stack) grid.get_child_at (2, row_count);
        var widget = name_stack.get_visible_child ();

        if (name_stack.get_visible_child_name () == "label")
        {
            var user_label = (Gtk.Label) widget;
            user_label.set_text (score.user);
        }
        else
        {
            var entry = (Gtk.Entry) widget;
            entry.text = score.user;
        }
    }

    /* Fill all labels from row row_count onwards with empty strings. */
    private void make_remaining_labels_empty (int row_count)
    {
        for (int i = row_count; i <= rows_to_display; i++)
        {
            for (int j = 0; j <= 1; j++)
            {
                var label = (Gtk.Label) grid.get_child_at (j, i);
                label.set_text ("");
            }

            var stack = (Gtk.Stack) grid.get_child_at (2, i);
            var label = (Gtk.Label) stack.get_visible_child ();
            label.set_text ("");
        }
    }
}

} /* namespace Scores */
} /* namespace Games */
