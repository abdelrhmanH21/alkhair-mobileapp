import 'package:equatable/equatable.dart';

abstract class AppConfigEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AppConfigFetchRequested extends AppConfigEvent {}
