/* -*- Mode: vala; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-
 *
 * Copyright © 2014 Nikhar Agrawal
 *
 * This file is part of libgames-scores.
 *
 * libgames-scores is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * libgames-scores is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with libgames-scores.  If not, see <http://www.gnu.org/licenses/>.
 */
namespace Games
{
namespace Scores
{
public enum Style
{
    PLAIN_DESCENDING,
    PLAIN_ASCENDING,
    TIME_DESCENDING,
    TIME_ASCENDING
}

/*public struct Category
{
    string key;
    string name;
}*/

public class Context : Object
{
    private Score? last_score = null;
    private Category? current_category = null;
    private Style style;
    /* A priority queue should enable us to easily fetch the top 10 scores */
    private Gee.HashMap <Category?, Gee.PriorityQueue<Score> > scores_per_category = new Gee.HashMap <Category?, Gee.PriorityQueue<Score>> ((owned) category_hash, (owned) category_equal);
    private string base_name;
    private string user_score_dir;
    private string dialog_label;
    private string user_name = Environment.get_real_name ();
    private Gtk.Window? window;
    /*This variable would be used to identify if the dialog has opened due to adding of a score*/
    public bool high_score_added = false;
    /*A signal that asks the game to provide the Category given the category key. This is mainly used to fetch category names.*/
    public signal Category request_category (string category_key);

    private CompareDataFunc<Score?> scorecmp;
    private static Gee.HashDataFunc<Category?> category_hash = (a) =>
    {
        return str_hash (a.name);
    };
    private static Gee.EqualDataFunc<Category?> category_equal = (a,b) =>
    {
        return str_equal (a.name, b.name);
    };

    public Category? active_category
    {
        get
        {
            return current_category;
        }
    }

    public string player_name
    {
        get
        {
            return user_name;
        }
        set
        {
            user_name = value;
        }
    }

    public Score? latest_score
    {
        get
        {
            return last_score;
        }

    }

    public Style score_style
    {
        get
        {
            return style;
        }
    }

    public List <Category?> get_categories ()
    {
        var categories = new List <Category?> ();
        var iterator = scores_per_category.map_iterator ();
        while (iterator.next ())
        {
            categories.append (iterator.get_key ());
        }
        return categories;
    }

    public Context (string app_name, string dialog_label, Gtk.Window? window, Style style = Style.PLAIN_DESCENDING)
    {
        this.window = window;
        this.style = style;
        if (style == Style.PLAIN_DESCENDING || style == Style.TIME_DESCENDING)
        {
            scorecmp = (a,b) =>
            {
                return (int) (b.score > a.score) - (int) (a.score > b.score);
            };
        }
        else
        {
            scorecmp = (a,b) =>
            {
                return (int) (b.score < a.score) - (int) (a.score < b.score);
            };
        }

        base_name = app_name;
        this.dialog_label = dialog_label;

        user_score_dir = Path.build_filename (Environment.get_user_data_dir (), base_name, null);
        try
        {
            load_scores_from_files ();
        }
        catch (Error e)
        {
            warning ("%s", e.message);
        }
    }

    /* this assumes that we intend to store ALL scores per category and not just the top 10. */
    public bool add_score (long score_value, Category category)
    {
        if (is_high_score (score_value, category) && window != null)
        {
            high_score_added = true;
        }

        var user = user_name;
        var current_time = new DateTime.now_local ().to_unix ();
        var time = current_time;
        Score score = new Score (score_value, time, user);
        /* check if category exists in the HashTable. Insert one if not */
        if (scores_per_category.has_key (category) ==  false)
        {
            // TODO: check if insert was successful. Glib.HashMap.set returns void
            scores_per_category.set (category, new Gee.PriorityQueue<Score> ((owned) scorecmp));
        }
        try
        {
            save_score_to_file (score, category);
            if (scores_per_category[category].add (score))
            {
                last_score = score;
                current_category = category;
            }

            return true;

        }
        catch (Error e)
        {
            warning ("%s", e.message);
            return false;
        }
    }

    /*Primarily used to change name of player*/
    public void update_score_name (Score old_score, string new_name, Category category)
    {
        var n_scores = new List<Score> ();
        var scores_of_this_category = scores_per_category[category];

        while (scores_of_this_category.size > 0)
        {
            var score = scores_of_this_category.poll ();
            if (score.user == old_score.user && score.time == old_score.time && score.score == old_score.score)
            {
                score.user = new_name;
                n_scores.append (score);
                break;
            }
            else
                n_scores.append (score);
        }

        /* insert the scores back into the priority queue*/
        n_scores.foreach ((x) => scores_of_this_category.add (x));
    }

    /* for debugging purposes */
    public void print_scores ()
    {
        var iterator = scores_per_category.map_iterator ();
        while (iterator.next ())
        {
            debug ("Key:%s", iterator.get_key ().name);
            var queue_iterator = iterator.get_value ().iterator ();
            while (queue_iterator.next ())
            {
                var time = new DateTime.from_unix_local (queue_iterator.get ().time);
                debug ("%ld\t%s\t%s",queue_iterator.get ().score, queue_iterator.get ().user, time.to_string());
            }
        }
        run_dialog ();
    }

    private void save_score_to_file (Score score, Category category) throws Error
    {
        /*create the directory if it doesn' exist*/
        if (!FileUtils.test (user_score_dir,FileTest.EXISTS))
        {
            if (DirUtils.create_with_parents (user_score_dir, 0766) == -1)
            {
                throw new FileError.FAILED ("Error: Could not create directory.");
            }
        }

        var filename = Path.build_filename (user_score_dir, category.key);

        var file = File.new_for_path (filename);

        var dos = new DataOutputStream (file.append_to (FileCreateFlags.NONE));

        var time_string = score.time.to_string ();

        dos.put_string (score.score.to_string () + " " +
                        time_string + " " +
                        score.user + "\n");
    }

    private void load_scores_from_files () throws Error
    {
        var directory = File.new_for_path (user_score_dir);

        if (!directory.query_exists ())
        {
            return;
        }

        var enumerator = directory.enumerate_children (FileAttribute.STANDARD_NAME, 0);

        FileInfo file_info;
        while ((file_info = enumerator.next_file ()) != null)
        {
            var category_key = file_info.get_name ();
            var category_full = request_category (category_key);
            debug ("%s\t%s",category_full.key, category_full.name);
            var filename = Path.build_filename (user_score_dir, category_key);

            var scores_of_single_category = new Gee.PriorityQueue<Score> ((owned) scorecmp);

            var file = File.new_for_path (filename);

            /* Open file for reading and wrap returned FileInputStream into a
             DataInputStream, so we can read line by line */
            var dis = new DataInputStream (file.read ());
            string line;
            /* Read lines until end of file (null) is reached */
            while ((line = dis.read_line (null)) != null)
            {
                //TODO: better error handling here?
                var tokens = line.split (" ", 3);
                if (tokens.length < 3)
                    throw new FileError.FAILED ("Failed to parse file for scores.");

                var score_value = long.parse (tokens[0]);
                var time = int64.parse (tokens[1]);
                var user = tokens[2];
                Score score = new Score (score_value, time, user);
                scores_of_single_category.add (score);
            }
            //TODO: How to retrieve name of category?
            Category category = new Category (category_key, category_key);
            scores_per_category.set (category, scores_of_single_category);
        }
    }

    private bool is_high_score (long score_value, Category category)
    {
        var best_scores = get_best_n_scores (category, 10);

	/*The given category doesn't yet exist and thus this score would be the first score and hence a high score.*/
	if (best_scores == null)
	    return true;

        if (best_scores.length () < 10)
            return true;

        var lowest = best_scores.nth_data (9).score;

        if (style == Style.PLAIN_ASCENDING || style == Style.TIME_ASCENDING)
            return score_value < lowest;

        return score_value > lowest;

    }
    /* Get a maximum of best n scores from the given category */
    public List<Score>? get_best_n_scores (Category category, int n)
    {
        if (!scores_per_category.has_key (category))
        {
		return null;
        }

        var n_scores = new List<Score> ();
        var scores_of_this_category = scores_per_category[category];

        for (int i = 0; i < n; i++)
        {
            if (scores_of_this_category.size == 0)
                break;
            n_scores.append (scores_of_this_category.poll ());
        }

        /* insert the scores back into the priority queue*/
        n_scores.foreach ((x) => scores_of_this_category.add (x));
        return n_scores;
    }

    public void run_dialog ()
    {
        if (window != null)
            new Dialog (this, dialog_label, window).run ();
    }
}

} /* namespace Scores */
} /* namespace Games */

/*TODO: Discuss following issues
 Retreive category name and category key from file names (sol: another file that stores the mapping)
 */
