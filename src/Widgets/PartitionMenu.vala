// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2016-2018 elementary LLC. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: Michael Aaron Murphy <michael@system76.com>
 */

public delegate void SetMount (Installer.Mount mount);

public delegate void UnsetMount (string partition);

public class Installer.PartitionMenu : Gtk.Popover {
    private Gtk.Grid grid;
    public bool disable_signals;
    public bool is_lvm;
    public Gtk.ComboBoxText type;
    public Gtk.ComboBoxText use_as;
    public Gtk.Entry custom;
    public Gtk.Label custom_label;
    public Gtk.Label format_label;
    public Gtk.Switch format_partition;
    public Gtk.Label type_label;
    public Gtk.Switch use_partition;
    public Distinst.FileSystemType original_filesystem;
    public string parent_disk;
    public string partition_path;

    public PartitionMenu (string path, string parent, Distinst.FileSystemType fs,
                          bool lvm, SetMount set_mount, UnsetMount unset_mount) {
        original_filesystem = fs;
        is_lvm = lvm;
        partition_path = path;
        parent_disk = parent;
        grid = new Gtk.Grid ();
        grid.column_spacing = 12;
        grid.row_spacing = 6;
        grid.margin = 12;

        var use_partition_label = new Gtk.Label ("Use partition:");
        format_label = new Gtk.Label ("Format:");
        var use_as_label = new Gtk.Label ("Use as:");
        custom_label = new Gtk.Label ("Custom:");
        type_label = new Gtk.Label ("Type:");

        custom_label.set_halign (Gtk.Align.END);
        format_label.set_halign (Gtk.Align.END);
        type_label.set_halign (Gtk.Align.END);
        use_as_label.set_halign (Gtk.Align.END);
        use_partition_label.set_halign (Gtk.Align.END);

        grid.attach (format_label, 0, 0);
        grid.attach (use_as_label, 0, 1);
        grid.attach (custom_label, 0, 2);
        grid.attach (type_label, 0, 3);

        use_partition = new Gtk.Switch ();
        use_partition.set_halign (Gtk.Align.START);
        use_partition.set_hexpand (true);

        format_partition = new Gtk.Switch ();
        format_partition.set_halign (Gtk.Align.START);

        string boot_partition;
        if (Distinst.bootloader_detect () == Distinst.PartitionTable.GPT) {
            boot_partition = "Boot (/boot/efi)";
        } else {
            boot_partition = "Boot (/boot)";
        }

        use_as = new Gtk.ComboBoxText ();
        use_as.append_text ("Root (/)");
        use_as.append_text ("Home (/home)");
        use_as.append_text (boot_partition);
        use_as.append_text ("Swap");
        use_as.append_text ("Custom");
        use_as.set_active (0);

        custom = new Gtk.Entry ();

        type = new Gtk.ComboBoxText ();
        type.append_text ("Default (ext4)");
        type.append_text ("fat16");
        type.append_text ("fat32");
        type.append_text ("btrfs");
        type.append_text ("xfs");
        type.append_text ("ntfs");
        type.set_active (0);

        grid.attach (format_partition, 1, 0);
        grid.attach (use_as, 1, 1);
        grid.attach (custom, 1, 2);
        grid.attach (type, 1, 3);

        var outer = new Gtk.Grid ();
        outer.row_spacing = 6;
        outer.column_spacing = 12;;
        outer.margin = 6;

        var outer_revealer = new Gtk.Revealer ();
        outer_revealer.add (grid);

        outer.attach (use_partition_label, 0, 0);
        outer.attach (use_partition, 1, 0);
        outer.attach (outer_revealer, 0, 1, 2, 1);

        this.add (outer);
        outer.show_all ();

        custom.set_visible (false);
        custom_label.set_visible (false);
        format_partition.set_visible (false);
        format_label.set_visible (false);

        use_as.changed.connect(() => {
            if (disable_signals) {
                return;
            }

            var active = use_as.get_active ();
            bool visible = active == 4;

            custom.set_visible (visible);
            custom_label.set_visible (visible);
            check_values (set_mount);

            if (active == 2) {
                if (Distinst.bootloader_detect () == Distinst.PartitionTable.GPT) {
                    type.set_active (2);
                } else {
                    type.set_active (0);
                }
                type_label.set_visible (true);
                type.set_visible (true);
                type.set_sensitive (false);
            } else if (active == 3) {
                type_label.set_visible (false);
                type.set_visible (false);
            } else {
                type_label.set_visible (true);
                type.set_visible (true);
                type.set_sensitive (true);
            }
        });

        type.changed.connect(() => {
            if (!disable_signals) {
                check_values (set_mount);
                set_format_sensitivity ();
            }
        });

        custom.changed.connect(() => {
            if (!disable_signals) {
                check_values (set_mount);
            }
        });

        use_partition.notify["active"].connect (() => {
            if (disable_signals) {
                return;
            }

            if (use_partition.active) {
                update_values (set_mount);
                set_format_sensitivity ();
            } else {
                unset_mount (partition_path);
            }

            outer_revealer.set_reveal_child (use_partition.active);
            format_partition.set_visible (use_partition.active);
            format_label.set_visible (use_partition.active);
        });
    }

    private void set_format_sensitivity () {
        bool is_sensitive = has_same_filesystem ();
        format_partition.active = !is_sensitive;
        format_partition.set_sensitive (is_sensitive);
    }

    private void check_values (SetMount set_mount) {
        if (values_ready ()) {
            update_values (set_mount);
        }
    }

    private void update_values (SetMount set_mount) {
        set_mount (new Installer.Mount (
            partition_path,
            parent_disk,
            get_mount (),
            (format_partition.active ? Mount.FORMAT : 0) + (is_lvm ? Mount.LVM : 0),
            get_file_system (),
            this
        ));
    }

    private bool has_same_filesystem () {
        return original_filesystem == get_file_system ();
    }

    private Distinst.FileSystemType get_file_system () {
        switch (type.get_active ()) {
            case 0:
                return Distinst.FileSystemType.EXT4;
            case 1:
                return Distinst.FileSystemType.FAT16;
            case 2:
                return Distinst.FileSystemType.FAT32;
            case 3:
                return Distinst.FileSystemType.BTRFS;
            case 4:
                return Distinst.FileSystemType.XFS;
            case 5:
                return Distinst.FileSystemType.NTFS;
            default:
                return Distinst.FileSystemType.NONE;
        }
    }

    private string get_mount () {
        switch (use_as.get_active ()) {
            case 0:
                return "/";
            case 1:
                return "/home";
            case 2:
                if (Distinst.bootloader_detect () == Distinst.PartitionTable.GPT) {
                    return "/boot/efi";
                } else {
                    return "/boot";
                }
            case 3:
                return "swap";
            default:
                return custom.get_text ();
        }
    }

    private bool values_ready () {
        return use_partition.active && (!custom_set () || custom_valid ());
    }

    private bool custom_set () {
        return use_as.get_active_text () == "Custom";
    }

    private bool custom_valid () {
        return custom.get_text ().has_prefix ("/");
    }
 }
