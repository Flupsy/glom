drop database if exists glom;
create database glom;
use glom;

create table logfiles (
    id              int auto_increment primary key,
    name            text,
    uri             text not null,
    last_retrieved  timestamp default current_timestamp
);

create table metrics (
    id              int auto_increment primary key,
    name            text,
    cmd             text not null,
    tail            boolean default false,
    do_subs         boolean defalt true
);

create table results (
    log_id          int,
    met_id          int,
    value           text,
    last_updated    timestamp default current_timestamp
);

