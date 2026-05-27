import 'package:equatable/equatable.dart';
import '../../data/models/app_config_model.dart';

abstract class AppConfigState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AppConfigInitial extends AppConfigState {}

class AppConfigLoaded extends AppConfigState {
  final AppConfigModel config;
  AppConfigLoaded(this.config);
  @override
  List<Object?> get props => [config];
}

class AppConfigLoadFailed extends AppConfigState {}
