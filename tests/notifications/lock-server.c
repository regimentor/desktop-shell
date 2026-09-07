// A private Wayland server exposing only the lock-notify protocol. It never
// creates a screen or locks the user's desktop. stdin accepts L/U/Q commands.
#include <wayland-server.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "lock-server.h"

static struct wl_display *display;
static struct wl_resource *clients[32];
static bool locked;
static void destroy_resource(struct wl_client *client, struct wl_resource *resource) { (void)client; wl_resource_destroy(resource); }
static void forget(struct wl_resource *resource) {
    for (int i=0; i<32; ++i) if (clients[i] == resource) clients[i] = NULL;
}
static const struct hyprland_lock_notification_v1_interface notification_impl = {destroy_resource};
static void subscribe(struct wl_client *client, struct wl_resource *manager, uint32_t id) {
    (void)manager;
    struct wl_resource *resource = wl_resource_create(client, &hyprland_lock_notification_v1_interface, 1, id);
    wl_resource_set_implementation(resource, &notification_impl, NULL, forget);
    for (int i=0; i<32; ++i) if (!clients[i]) { clients[i]=resource; break; }
    if (locked) hyprland_lock_notification_v1_send_locked(resource);
}
static const struct hyprland_lock_notifier_v1_interface manager_impl = {destroy_resource, subscribe};
static void bind_manager(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    (void)data; (void)version;
    struct wl_resource *resource = wl_resource_create(client, &hyprland_lock_notifier_v1_interface, 1, id);
    wl_resource_set_implementation(resource, &manager_impl, NULL, NULL);
}
static int command(int fd, uint32_t mask, void *data) {
    (void)mask; (void)data;
    char buffer[32]; ssize_t count = read(fd,buffer,sizeof(buffer));
    if (count <= 0) { wl_display_terminate(display); return 0; }
    for (ssize_t i=0;i<count;++i) {
        if (buffer[i]=='Q') { wl_display_terminate(display); return 0; }
        if (buffer[i]!='L' && buffer[i]!='U') continue;
        bool next=buffer[i]=='L'; if (locked==next) continue; locked=next;
        for (int j=0;j<32;++j) if (clients[j]) {
            if (locked) hyprland_lock_notification_v1_send_locked(clients[j]);
            else hyprland_lock_notification_v1_send_unlocked(clients[j]);
        }
    }
    wl_display_flush_clients(display);
    return 0;
}
int main(int argc, char **argv) {
    locked=argc>1 && strcmp(argv[1],"locked")==0;
    display=wl_display_create();
    if (!display || wl_display_add_socket(display,"daevox-lock-test")<0) return 1;
    wl_global_create(display,&hyprland_lock_notifier_v1_interface,1,NULL,bind_manager);
    wl_event_loop_add_fd(wl_display_get_event_loop(display),STDIN_FILENO,WL_EVENT_READABLE,command,NULL);
    wl_display_run(display); wl_display_destroy_clients(display); wl_display_destroy(display); return 0;
}
